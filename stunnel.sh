#!/bin/bash
# نصب تازه stunnel
sudo apt update
sudo apt install -y stunnel4

# ایجاد دایرکتوری کانفیگ
sudo mkdir -p /etc/stunnel

# ایجاد گواهی SSL
sudo openssl req -new -x509 -days 365 -nodes \
    -out /etc/stunnel/server.pem \
    -keyout /etc/stunnel/server.key \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=stunnel-server"

# تنظیم مجوزها
sudo chmod 600 /etc/stunnel/server.key
sudo chmod 644 /etc/stunnel/server.pem

# ایجاد کانفیگ ساده
sudo cat > /etc/stunnel/stunnel.conf << 'EOF'
cert = /etc/stunnel/server.pem
key = /etc/stunnel/server.key
pid = /var/run/stunnel4/stunnel.pid

[vpn-server]
accept = 443
connect = 127.0.0.1:1080
EOF

# ایجاد دایرکتوری PID
sudo mkdir -p /var/run/stunnel4
sudo chown stunnel4:stunnel4 /var/run/stunnel4

# فعال کردن stunnel
echo "ENABLED=1" | sudo tee /etc/default/stunnel4

# شروع سرویس
sudo systemctl enable stunnel4
sudo systemctl start stunnel4

# بررسی وضعیت
sudo systemctl status stunnel4
