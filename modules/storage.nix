{ config, lib, pkgs, ... }:

let
  secrets = builtins.fromJSON (
    builtins.readFile config.age.secrets.all.path
  );
in
{
  age.secrets.all = {
    file = ../secrets/couchdb.age;
    owner = "root";
    mode = "0600";
  };

services.couchdb = {
    enable = true;
    
    adminUser = secrets.adminUser;
    adminPass = secrets.adminPass;

    bindAddress = "0.0.0.0";
  };
}