{ config, lib, pkgs, ... }:

{
  # 1. Объявляем секрет как EnvironmentFile для systemd
  # Внутри вашего файла `../secrets/couchdb.age` текст должен быть в формате:
  # COUCHDB_PASSWORD=ваш_очень_секретный_пароль
  age.secrets.couchdb-env = {
    file = ../secrets/couchdb.age;
    owner = "couchdb";
    mode = "0600";
  };

  services.couchdb = {
    enable = true;
    adminUser = "admin";
    
    # Сюда мы передаем специальную переменную окружения, 
    # которую CouchDB подхватит автоматически при запуске.
    adminPass = "$COUCHDB_PASSWORD"; 

    bindAddress = "0.0.0.0";
  };

  # 2. Подкидываем файл с секретом в службу CouchDB
  systemd.services.couchdb.serviceConfig.EnvironmentFile = config.age.secrets.couchdb-env.path;
}