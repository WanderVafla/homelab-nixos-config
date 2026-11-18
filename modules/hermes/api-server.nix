# Hermes API server (OpenAI-compatible, with sessions and SSE streaming) for the owner's desktop
# chat. It listens inside the container; only the host can reach the container's veth address,
# and the host exposes it solely through `hermes-chat` over SSH (modules/base/hermes-chat).
{ ... }:

let
  port = 8642; # apiPort in modules/base/hermes-chat/default.nix
in
{
  services.hermes-agent = {
    # API_SERVER_KEY, bind-mounted by the host. The API server enables itself when the key is set.
    environmentFiles = [ "/run/secrets/hermes-api-env" ];

    environment = {
      # The container's own address is not known here, and the container has no other network.
      API_SERVER_HOST = "0.0.0.0";
      API_SERVER_PORT = toString port;
    };
  };

  # The container's only interface is the veth link to the host.
  networking.firewall.allowedTCPPorts = [ port ];
}
