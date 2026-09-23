{
  config,
  pkgs,
  inputs,
  sharedConfig,
  ...
}:
let
  cfg = sharedConfig;
  argocdCfg = cfg.argocd;
  authentikCfg = cfg.authentik;

  helmValues = builtins.toJSON {
    global = {
      inherit (argocdCfg) domain;
    };

    server = {
      extraArgs = [ "--insecure" ]; # TLS は Cloudflare Tunnel 側で終端するため
      metrics.enabled = true;

      # LAN 内 LoadBalancer Service（固定 VIP）。
      # API クライアント向けの内部エンドポイント。外部経路は ClusterIP 側を使う。
      service = {
        type = "LoadBalancer";
        annotations = {
          "io.cilium/lb-ipam-ips" = cfg.lbIpam.argocd;
        };
      };
    };

    controller = {
      metrics.enabled = true;
    };

    applicationSet = {
      metrics.enabled = true;
    };

    configs = {
      cm = {
        url = "https://${argocdCfg.domain}";
        # KSOPS（Kustomize + SOPS）プラグインを有効化
        "kustomize.buildOptions" = "--enable-alpha-plugins --enable-exec";
        # Web Terminal（exec）機能。有効にするかは値レイヤの判断。
        # 上の kustomize.buildOptions の --enable-exec とは別物で、
        # あちらは KSOPS の exec plugin なので外すと SOPS 復号が止まる。
        "exec.enabled" = if argocdCfg.webTerminal then "true" else "false";
        "exec.shells" = "bash,sh"; # Linux Pod のみ想定
        "dex.config" = ""; # Dex を無効化（外部 OIDC を直接使用）
        "oidc.config" = builtins.toJSON {
          name = "Authentik";
          issuer = "${authentikCfg.baseUrl}/application/o/argocd/";
          clientID = "$oidc.authentik.clientID";
          clientSecret = "$oidc.authentik.clientSecret";
          requestedScopes = [
            "openid"
            "profile"
            "email"
            "groups"
          ];
        };

        # ローカル apiKey アカウント: OIDC を介さない長寿命 Bearer token 用のサービスアカウント。
        # 権限は下の role:mcp で get/sync/action/create/update に限定 (delete は付与しない)
        "accounts.mcp" = "apiKey";
      };

      rbac = {
        "policy.csv" = ''
          p, role:app-manager, applications, get, */*, allow
          p, role:app-manager, applications, create, */*, allow
          p, role:app-manager, applications, update, */*, allow
          p, role:app-manager, applications, delete, */*, allow
          p, role:app-manager, applications, sync, */*, allow
          p, role:app-manager, applications, action/*, */*, allow
          p, role:app-manager, logs, get, */*, allow
          p, role:app-manager, exec, create, */*, allow
          p, role:app-manager, projects, get, *, allow

          p, role:mcp, applications, get, */*, allow
          p, role:mcp, applications, sync, */*, allow
          p, role:mcp, applications, action/*, */*, allow
          p, role:mcp, applications, create, */*, allow
          p, role:mcp, applications, update, */*, allow
          p, role:mcp, projects, get, *, allow
          p, role:mcp, repositories, get, *, allow
          p, role:mcp, clusters, get, *, allow
          p, role:mcp, logs, get, */*, allow

          g, ${cfg.argocd.rbac.adminGroup}, role:admin
          g, ${cfg.argocd.rbac.userGroup}, role:app-manager
          g, mcp, role:mcp
        '';
        # ロール未割り当ての認証済みユーザーに何を許すか。値レイヤの判断。
        "policy.default" = argocdCfg.rbac.defaultPolicy;
        "scopes" = "[groups]";
      };

      params = {
        "server.insecure" = true; # TLS は Cloudflare Tunnel 側で終端するため
      };
    };

    dex = {
      enabled = false; # Authentik OIDC を直接使用
    };

    notifications = {
      enabled = false;
    };

    repoServer = {
      metrics.enabled = true;

      # BestEffort QoS 脱却（Burstable へ）+ probe タイムアウト緩和
      resources = argocdCfg.repoServer.resources;
      livenessProbe = {
        timeoutSeconds = argocdCfg.repoServer.livenessProbeTimeoutSeconds;
      };
      readinessProbe = {
        timeoutSeconds = argocdCfg.repoServer.readinessProbeTimeoutSeconds;
      };

      initContainers = [
        {
          name = "install-ksops";
          image = argocdCfg.ksopsImage;
          command = [
            "/bin/sh"
            "-c"
          ];
          args = [ "cp /usr/local/bin/ksops /custom-tools/ksops" ];
          volumeMounts = [
            {
              mountPath = "/custom-tools";
              name = "custom-tools";
            }
          ];
        }
      ];

      volumes = [
        {
          name = "custom-tools";
          emptyDir = { };
        }
        {
          name = "sops-age";
          secret = {
            secretName = "sops-age-key";
          };
        }
      ];

      volumeMounts = [
        {
          mountPath = "/usr/local/bin/ksops";
          name = "custom-tools";
          subPath = "ksops";
        }
        {
          mountPath = "/home/argocd/.config/sops/age";
          name = "sops-age";
        }
      ];

      # SOPS が Age 鍵ファイルを見つけるための環境変数
      env = [
        {
          name = "XDG_CONFIG_HOME";
          value = "/home/argocd/.config";
        }
        {
          name = "SOPS_AGE_KEY_FILE";
          value = "/home/argocd/.config/sops/age/keys.txt";
        }
      ];
    };
  };

  helmChartFile = pkgs.writeText "argocd-helmchart.yaml" helmChartManifest;

  helmChartManifest = ''
    apiVersion: helm.cattle.io/v1
    kind: HelmChart
    metadata:
      name: argocd
      namespace: kube-system
    spec:
      repo: https://argoproj.github.io/argo-helm
      chart: argo-cd
      version: "${argocdCfg.helmChartVersion}"
      targetNamespace: ${argocdCfg.namespace}
      createNamespace: true
      valuesContent: |-
        ${builtins.replaceStrings [ "\n" ] [ "\n        " ] helmValues}
  '';

in
{

  sops.secrets = {
    "argocd/oidc_client_id" = {
      sopsFile = "${inputs.self}/${cfg.sops.files.argocd}";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    "argocd/oidc_client_secret" = {
      sopsFile = "${inputs.self}/${cfg.sops.files.argocd}";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    "argocd/github_deploy_key" = {
      sopsFile = "${inputs.self}/${cfg.sops.files.argocd}";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    "argocd/ghcr_pat" = {
      sopsFile = "${inputs.self}/${cfg.sops.files.argocd}";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    # k8s専用Age秘密鍵（KSOPS復号用、ArgoCD repo-serverに投入）
    "k8s/age_key" = {
      sopsFile = "${inputs.self}/${cfg.sops.files.k8sAgeKey}";
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };

  systemd.services.argocd-secrets = {
    description = "ArgoCD Kubernetes Secrets Setup";
    after = [ "k3s.service" ];
    requires = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];

    path = [
      pkgs.kubectl
      pkgs.coreutils
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30s";
      TimeoutStartSec = "600"; # k3s起動待ちを含むため長めに設定
    };

    script =
      let
        oidcClientIdPath = config.sops.secrets."argocd/oidc_client_id".path;
        oidcClientSecretPath = config.sops.secrets."argocd/oidc_client_secret".path;
        deployKeyPath = config.sops.secrets."argocd/github_deploy_key".path;
        k8sAgeKeyPath = config.sops.secrets."k8s/age_key".path;
      in
      ''
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

        echo "Waiting for k3s API server..."
        until kubectl cluster-info >/dev/null 2>&1; do
          sleep 5
        done

        echo "Applying ArgoCD HelmChart manifest..."
        kubectl apply -f ${helmChartFile}

        echo "Waiting for ArgoCD namespace..."
        until kubectl get ns ${argocdCfg.namespace} >/dev/null 2>&1; do
          sleep 5
        done

        echo "Waiting for ArgoCD server deployment..."
        until kubectl -n ${argocdCfg.namespace} get deploy argocd-server >/dev/null 2>&1; do
          sleep 10
        done

        echo "Applying OIDC credentials..."
        OIDC_CLIENT_ID=$(cat ${oidcClientIdPath})
        OIDC_CLIENT_SECRET=$(cat ${oidcClientSecretPath})

        kubectl -n ${argocdCfg.namespace} create secret generic argocd-secret \
          --from-literal=oidc.authentik.clientID="$OIDC_CLIENT_ID" \
          --from-literal=oidc.authentik.clientSecret="$OIDC_CLIENT_SECRET" \
          --dry-run=client -o yaml | kubectl apply -f -

        echo "Applying GitHub Deploy Key..."
        kubectl -n ${argocdCfg.namespace} create secret generic ${argocdCfg.gitopsRepoSecretName} \
          --from-file=sshPrivateKey=${deployKeyPath} \
          --from-literal=type=git \
          --from-literal=url=${argocdCfg.gitopsRepoUrl} \
          --dry-run=client -o yaml | kubectl apply -f -
        kubectl -n ${argocdCfg.namespace} label secret ${argocdCfg.gitopsRepoSecretName} \
          argocd.argoproj.io/secret-type=repository --overwrite

        echo "Applying k8s Age key for KSOPS..."
        kubectl -n ${argocdCfg.namespace} create secret generic sops-age-key \
          --from-file=keys.txt=${k8sAgeKeyPath} \
          --dry-run=client -o yaml | kubectl apply -f -

        echo "Restarting ArgoCD server to apply OIDC config..."
        kubectl -n ${argocdCfg.namespace} rollout restart deploy argocd-server

        echo "ArgoCD secrets setup completed."
      '';
  };
}
