# The owner's login account and its SSH keys.
{ ... }:

{
  users.users.WanderVafla = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGgQH1mxiZirrI7GHXBJj0kwKp0im30JWmnxezLH+pkp vladyslav@JTlaptopNix"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGO3Ob1rxJ7nUEHA73izFtCdUSZcViRVnhLq7lioyzAb procenkovladik1@gmail.com"
    ];
  };
}
