# Deployment
Depends on Systemd
From this directory, execute the following to start daily postgres db-dumps retained for a year:
``` bash
sudo install -m 750 ./postgres-backup.sh \
  /usr/local/sbin/backup-postgres.sh

sudo install -m 644 ./postgres-backup.service \
  /etc/systemd/system/

sudo install -m 644 ./postgres-backup.timer \
  /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now postgres-backup.timer
```