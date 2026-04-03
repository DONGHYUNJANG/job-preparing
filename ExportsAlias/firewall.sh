firewall-cmd --permanent --add-port=1521/tcp
firewall-cmd --reload
firewall-cmd --list-ports | grep 1521
