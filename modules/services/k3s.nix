# Single-node k3s cluster for agent workloads (AX + Agent Substrate).
#
# Wraps upstream services.k3s: disables traefik/servicelb (host nginx owns
# 80/443), exposes a registries option for plain-HTTP containerd mirrors
# (no auth support — credentials would land in the world-readable store;
# use a publicly pullable registry), and mirrors root's kubeconfig to the
# user's ~/.kube/config so the ax CLI and kubectl work unprivileged.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.k3s;
in
{
  options.k3s = {
    enable = mkEnableOption "single-node k3s cluster";

    registries = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          endpoint = mkOption {
            type = types.str;
            description = "Mirror endpoint URL for this registry host.";
          };
        };
      });
      default = { };
      example = {
        "127.0.0.1:3000".endpoint = "http://127.0.0.1:3000";
      };
      description = "Container registries containerd should mirror (k3s registries.yaml).";
    };

    kubeconfigUser = mkOption {
      type = types.str;
      default = "jay";
      description = "User that receives a synced copy of the kubeconfig.";
    };
  };

  config = mkIf cfg.enable {
    services.k3s = {
      enable = true;
      role = "server";
      extraFlags = [
        "--disable=traefik"
        "--disable=servicelb"
        # Agent Substrate needs the pod-certificate APIs; not on by default
        # as of Kubernetes 1.36 (see hack/create-kind-cluster.sh upstream).
        "--kube-apiserver-arg=feature-gates=ClusterTrustBundle=true,ClusterTrustBundleProjection=true,PodCertificateRequest=true"
        "--kube-apiserver-arg=runtime-config=certificates.k8s.io/v1beta1=true"
        # Single-node install pulls ~570MB of control-plane images; parallel
        # pulls keep workloads from missing readiness deadlines in the queue.
        "--kubelet-arg=serialize-image-pulls=false"
        # This host has a 916G root with chronic ~90% usage; the kubelet
        # defaults (imagefs.available<15%, GC at 85%) would sit in permanent
        # eviction pressure with plenty of absolute space left.
        "--kubelet-arg=eviction-hard=imagefs.available<3%,nodefs.available<3%"
        "--kubelet-arg=eviction-minimum-reclaim=imagefs.available=2%,nodefs.available=2%"
        "--kubelet-arg=image-gc-high-threshold=95"
      ];
    };

    environment.etc."rancher/k3s/registries.yaml".source = (pkgs.formats.yaml { }).generate "registries.yaml" {
      mirrors = mapAttrs (_: r: { endpoint = [ r.endpoint ]; }) cfg.registries;
    };

    # k3s rewrites /etc/rancher/k3s/k3s.yaml (mode 600, root) on cert
    # changes; watch it and keep a user-owned copy in ~/.kube/config.
    systemd.paths.k3s-kubeconfig-sync = {
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathChanged = "/etc/rancher/k3s/k3s.yaml";
    };

    systemd.services.k3s-kubeconfig-sync = {
      description = "Sync k3s kubeconfig for unprivileged use";
      after = [ "k3s.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ConditionPathExists = "/etc/rancher/k3s/k3s.yaml";
      };
      script = ''
        install -D -m 600 -o ${cfg.kubeconfigUser} \
          /etc/rancher/k3s/k3s.yaml \
          /home/${cfg.kubeconfigUser}/.kube/config
      '';
    };
  };
}
