# The owner's login account and its SSH keys.
{ ... }:

{
  users.users.WanderVafla = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    # Keep the user manager running between SSH sessions. Otherwise the last session closing
    # during a deploy stops user@1000 while switch-to-configuration reloads user units, the
    # switch fails with "Connection is closed" and the deployer rolls back.
    linger = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGgQH1mxiZirrI7GHXBJj0kwKp0im30JWmnxezLH+pkp vladyslav@JTlaptopNix"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGO3Ob1rxJ7nUEHA73izFtCdUSZcViRVnhLq7lioyzAb procenkovladik1@gmail.com"
    ];
  };
}
