# Deployment
Depends on Systemd
From this directory, execute the following to start daily postgres db-dumps retained for a year:
``` bash
sudo install -o root -g backup -m 750 \
  ./postgres-backup.sh \
  /usr/local/sbin/postgres-backup.sh

sudo install -m 644 \
  ./postgres-backup.service \
  /etc/systemd/system/postgres-backup.service

sudo install -m 644 \
  ./postgres-backup.timer \
  /etc/systemd/system/postgres-backup.timer

sudo systemctl daemon-reload
sudo systemctl enable --now postgres-backup.timer
```