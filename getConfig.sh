#!/bin/bash

# رنگ‌های ترمینال
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # بدون رنگ

# نمایش لوگو
echo -e "${BLUE}"
echo "===================================================================="
echo " __      _____  _____               ___           _        _ _"
echo " \ \    / /__ \|  __ \             |_ _|_ __  ___| |_ __ _| | | ___ _ __"
echo "  \ \  / /   ) | |__) |__ _ _   _    | || '_ \/ __| __/ _\` | | |/ _ \ '__|"
echo "   \ \/ /   / /|  _  // _\` | | | |   | || | | \__ \ || (_| | | |  __/ |"
echo "    \  /   / /_| | \ \ (_| | |_| |  |___|_| |_|___/\__\__,_|_|_|\___|_|"
echo "     \/   |____|_|  \_\__,_|\__, |"
echo "                             __/ |"
echo "                            |___/"
echo "===================================================================="
echo -e "${NC}"

# چک کردن دسترسی روت
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[خطا] این اسکریپت باید با دسترسی روت اجرا شود${NC}"
    exit 1
fi

# دریافت سیستم عامل
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        echo -e "${RED}سیستم عامل شما پشتیبانی نمی‌شود${NC}"
        exit 1
    fi
}

# نصب پیش‌نیازها
install_dependencies() {
    echo -e "${YELLOW}[اطلاعات] در حال نصب پیش‌نیازها...${NC}"
    
    if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
        apt update -y
        apt install -y python3 python3-pip iptables curl wget git
    elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        yum update -y
        yum install -y python3 python3-pip iptables curl wget git
    else
        echo -e "${RED}[خطا] سیستم عامل شما پشتیبانی نمی‌شود${NC}"
        exit 1
    fi
    
    # نصب ماژول‌های پایتون
    pip3 install flask requests python-iptables
    
    echo -e "${GREEN}[موفقیت] پیش‌نیازها با موفقیت نصب شدند${NC}"
}

# تنظیم لیست آی‌پی‌های سفید
setup_whitelist() {
    echo -e "${YELLOW}[اطلاعات] در حال تنظیم لیست آی‌پی‌های سفید...${NC}"
    
    # فایل لیست سفید
    WHITELIST_FILE="whitelist.txt"
    
    # اگر فایل موجود است، آن را بخوانیم
    if [ -f "$WHITELIST_FILE" ]; then
        echo -e "${YELLOW}فایل لیست سفید یافت شد${NC}"
        WHITELIST=$(cat "$WHITELIST_FILE")
    else
        # در غیر این صورت از کاربر بپرسیم
        echo -e "${YELLOW}فایل لیست سفید یافت نشد. لطفاً آی‌پی‌های سفید را وارد کنید (با کاما جدا کنید):${NC}"
        read -p "لیست آی‌پی‌های سفید: " WHITELIST
        
        # ذخیره در فایل برای استفاده‌های بعدی
        echo "$WHITELIST" > "$WHITELIST_FILE"
    fi
    
    echo -e "${GREEN}[موفقیت] لیست آی‌پی‌های سفید تنظیم شد${NC}"
}

# ایجاد فایل پایتون
create_python_script() {
    echo -e "${YELLOW}[اطلاعات] در حال ایجاد اسکریپت پایتون...${NC}"
    
    cat > v2ray_config_server.py << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import json
import logging
import ipaddress
import subprocess
import threading
import time
import socket
import requests
from flask import Flask, jsonify, request, abort
from functools import wraps
import iptables
from werkzeug.serving import make_server
import configparser
import signal

# تنظیم لاگینگ
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/var/log/v2ray_config_server.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("v2ray_config_server")

# مسیر پیکربندی
CONFIG_PATH = '/etc/v2ray_config_server.ini'

# ایجاد فایل پیکربندی اگر وجود نداشته باشد
def create_default_config():
    if not os.path.exists(CONFIG_PATH):
        config = configparser.ConfigParser()
        config['SERVER'] = {
            'Port': '8008',
            'XUIEndpoint': 'http://127.0.0.1:80/panel',
            'XUIUsername': 'zahed',
            'XUIPassword': 'zahed2341',
            'AllowedIPs': 'WHITELIST_PLACEHOLDER',
            'CheckRealIP': 'True',
            'AutoRestartEnabled': 'True',
            'APIEndpoint': '/api/configs'
        }
        
        with open(CONFIG_PATH, 'w') as f:
            config.write(f)
        
        # تنظیم دسترسی فایل
        os.chmod(CONFIG_PATH, 0o600)
        
        logger.info(f"فایل پیکربندی پیش‌فرض در {CONFIG_PATH} ایجاد شد")

# خواندن تنظیمات
def read_config():
    create_default_config()
    
    config = configparser.ConfigParser()
    config.read(CONFIG_PATH)
    
    return {
        'port': int(config['SERVER']['Port']),
        'xui_endpoint': config['SERVER']['XUIEndpoint'],
        'xui_username': config['SERVER']['XUIUsername'],
        'xui_password': config['SERVER']['XUIPassword'],
        'allowed_ips': config['SERVER']['AllowedIPs'].split(','),
        'check_real_ip': config['SERVER'].getboolean('CheckRealIP'),
        'auto_restart': config['SERVER'].getboolean('AutoRestartEnabled'),
        'api_endpoint': config['SERVER']['APIEndpoint']
    }

# کلاس سرور وب
class ConfigServer:
    def __init__(self):
        self.config = read_config()
        self.app = Flask(__name__)
        self.setup_routes()
        self.server = None
        
        # ذخیره سشن XUI
        self.xui_session = None
        self.xui_token = None
        self.last_login_time = 0
        
        # لیست آی‌پی‌های مجاز (به‌روزرسانی دوره‌ای)
        self.authorized_ips = set(self.config['allowed_ips'])
        
        # مسیر مربوط به CDN‌ها برای تشخیص آی‌پی واقعی
        self.cdn_networks = self.load_cdn_networks()
    
    def load_cdn_networks(self):
        """بارگذاری لیست شبکه‌های CDN برای جلوگیری از دسترسی"""
        cdn_networks = []
        try:
            # CloudFlare
            cloudflare_ips = requests.get('https://www.cloudflare.com/ips-v4').text.strip().split('\n')
            for ip_range in cloudflare_ips:
                cdn_networks.append(ipaddress.ip_network(ip_range))
            
            # برای شبکه‌های دیگر مانند Arvan Cloud می‌توانید منابع مشابه را اضافه کنید
            arvan_networks = [
                '185.143.232.0/22',
                '92.114.16.0/20',
                '2.146.0.0/20',
                # سایر محدوده‌های آروان را می‌توانید اضافه کنید
            ]
            
            for ip_range in arvan_networks:
                cdn_networks.append(ipaddress.ip_network(ip_range))
                
        except Exception as e:
            logger.error(f"خطا در بارگذاری لیست شبکه‌های CDN: {e}")
        
        logger.info(f"تعداد {len(cdn_networks)} شبکه CDN برای فیلتر کردن بارگذاری شد")
        return cdn_networks
    
    def is_cdn_ip(self, ip_addr):
        """بررسی اینکه آیا آی‌پی متعلق به یک CDN است یا خیر"""
        try:
            ip = ipaddress.ip_address(ip_addr)
            for network in self.cdn_networks:
                if ip in network:
                    return True
            return False
        except:
            return True  # در صورت خطا، به طور پیش‌فرض آی‌پی را مشکوک تلقی می‌کنیم
    
    def get_real_ip(self):
        """گرفتن آی‌پی واقعی کاربر با در نظر گرفتن هدرهای مختلف"""
        if not request.remote_addr:
            return None
            
        ip = request.remote_addr
        
        # بررسی اگر آی‌پی از CDN باشد
        if self.config['check_real_ip'] and self.is_cdn_ip(ip):
            # تلاش برای استخراج آی‌پی واقعی از هدرها
            headers_to_check = [
                'X-Forwarded-For',
                'X-Real-IP',
                'CF-Connecting-IP',
                'True-Client-IP'
            ]
            
            for header in headers_to_check:
                if header in request.headers:
                    # گرفتن اولین آی‌پی در لیست (معمولاً آی‌پی اصلی کاربر)
                    potential_ip = request.headers[header].split(',')[0].strip()
                    
                    try:
                        # تست اعتبار آی‌پی
                        ipaddress.ip_address(potential_ip)
                        if not self.is_cdn_ip(potential_ip):
                            ip = potential_ip
                            break
                    except:
                        continue
        
        return ip
    
    def setup_routes(self):
        """تنظیم مسیرهای API"""
        @self.app.route(self.config['api_endpoint'], methods=['GET'])
        def get_configs():
            # بررسی آی‌پی کاربر
            client_ip = self.get_real_ip()
            
            if not client_ip:
                abort(403, description="آی‌پی شما قابل شناسایی نیست")
            
            # بررسی اینکه آیا آی‌پی در لیست مجاز است
            if client_ip not in self.authorized_ips:
                # اضافه کردن آی‌پی به لیست مجاز و فایروال
                self.add_authorized_ip(client_ip)
                logger.info(f"آی‌پی جدید {client_ip} به لیست مجاز اضافه شد")
            
            # دریافت کانفیگ‌ها از XUI
            try:
                configs = self.fetch_xui_configs()
                return jsonify(configs)
            except Exception as e:
                logger.error(f"خطا در دریافت کانفیگ‌ها: {e}")
                return jsonify({"error": "خطا در دریافت کانفیگ‌ها"}), 500
    
    def add_authorized_ip(self, ip):
        """اضافه کردن آی‌پی به لیست مجاز و اعمال قوانین فایروال"""
        if ip in self.authorized_ips:
            return
            
        self.authorized_ips.add(ip)
        
        # اعمال قوانین فایروال برای این آی‌پی
        try:
            # اجازه اتصال به پورت V2Ray (معمولاً 1080، 1081، و غیره)
            v2ray_ports = self.get_v2ray_ports()
            
            for port in v2ray_ports:
                subprocess.run([
                    'iptables', '-A', 'INPUT', '-s', ip, '-p', 'tcp', 
                    '--dport', str(port), '-j', 'ACCEPT'
                ], check=True)
                
                subprocess.run([
                    'iptables', '-A', 'INPUT', '-s', ip, '-p', 'udp', 
                    '--dport', str(port), '-j', 'ACCEPT'
                ], check=True)
            
            # ذخیره تنظیمات فایروال
            subprocess.run(['iptables-save'], check=True)
            
            # به‌روزرسانی فایل پیکربندی
            self.update_allowed_ips_in_config()
            
        except Exception as e:
            logger.error(f"خطا در تنظیم قوانین فایروال برای آی‌پی {ip}: {e}")
    
    def update_allowed_ips_in_config(self):
        """به‌روزرسانی لیست آی‌پی‌های مجاز در فایل پیکربندی"""
        try:
            config = configparser.ConfigParser()
            config.read(CONFIG_PATH)
            
            config['SERVER']['AllowedIPs'] = ','.join(self.authorized_ips)
            
            with open(CONFIG_PATH, 'w') as f:
                config.write(f)
                
            logger.info("لیست آی‌پی‌های مجاز در فایل پیکربندی به‌روزرسانی شد")
        except Exception as e:
            logger.error(f"خطا در به‌روزرسانی فایل پیکربندی: {e}")
    
    def get_v2ray_ports(self):
        """دریافت پورت‌های V2Ray از طریق API یا فایل پیکربندی"""
        ports = [1080, 1081]  # پورت‌های پیش‌فرض
        
        # در اینجا می‌توان کد استخراج پورت‌های واقعی از XUI را پیاده‌سازی کرد
        # برای مثال، با استفاده از API دریافت پورت‌ها یا خواندن فایل کانفیگ
        
        return ports
    
    def login_to_xui(self):
        """ورود به پنل 3x-ui محلی و دریافت توکن"""
        if (time.time() - self.last_login_time) < 3600:  # اگر کمتر از یک ساعت گذشته باشد
            return self.xui_session, self.xui_token
            
        try:
            session = requests.Session()
            
            # برای 3x-ui باید از فرم استفاده کرد (Form-data)
            login_data = {
                "username": self.config['xui_username'],
                "password": self.config['xui_password']
            }
            
            # آدرس لاگین 3x-ui محلی
            login_url = f"{self.config['xui_endpoint'].split('/panel')[0]}/login"
            
            response = session.post(
                login_url,
                data=login_data,  # استفاده از data به جای json
                timeout=10
            )
            
            if response.status_code == 200:
                # بررسی ورود موفق با استفاده از سشن
                self.xui_session = session
                self.xui_token = ""  # 3x-ui از کوکی برای احراز هویت استفاده می‌کند
                self.last_login_time = time.time()
                logger.info("ورود موفق به پنل 3x-ui محلی")
                return session, self.xui_token
            
            logger.error(f"خطا در ورود به 3x-ui محلی: کد وضعیت {response.status_code}")
            return None, None
            
        except Exception as e:
            logger.error(f"خطا در اتصال به 3x-ui محلی: {e}")
            return None, None
    
    def fetch_xui_configs(self):
        """دریافت کانفیگ‌های V2Ray از 3x-ui"""
        session, token = self.login_to_xui()
        
        if not session:
            raise Exception("خطا در اتصال به پنل 3x-ui")
        
        # مسیر API برای 3x-ui
        try:
            # استفاده از آدرس دقیق API مطابق با مستندات 3x-ui
            api_url = f"{self.config['xui_endpoint']}/api/inbounds/list"
            
            headers = {
                'Accept': 'application/json'
            }
                
            response = session.get(api_url, headers=headers)
            
            if response.status_code == 200:
                configs = response.json()
                return self.process_configs(configs)
            else:
                logger.error(f"خطا در دریافت کانفیگ‌ها: {response.status_code} - {response.text}")
                raise Exception(f"خطا در دریافت کانفیگ‌ها: {response.status_code}")
                
        except Exception as e:
            logger.error(f"خطا در درخواست کانفیگ‌ها: {e}")
            raise
    
    def process_configs(self, configs):
        """پردازش کانفیگ‌های V2Ray و فرمت‌دهی آن‌ها برای 3x-ui"""
        # ساختار داده‌های 3x-ui را بررسی می‌کنیم
        
        if 'obj' in configs and isinstance(configs['obj'], list):
            return configs['obj']
        elif 'success' in configs and 'obj' in configs:
            # فرمت خاص 3x-ui
            if configs['success'] and isinstance(configs['obj'], list):
                return configs['obj']
            else:
                return configs
        elif isinstance(configs, list):
            return configs
        else:
            return {"raw_data": configs}
    
    def start(self):
        """شروع سرور وب"""
        try:
            self.server = make_server('0.0.0.0', self.config['port'], self.app)
            logger.info(f"سرور روی پورت {self.config['port']} در حال اجرا است")
            self.server.serve_forever()
        except Exception as e:
            logger.critical(f"خطا در اجرای سرور: {e}")
            sys.exit(1)
    
    def stop(self):
        """توقف سرور وب"""
        if self.server:
            self.server.shutdown()
            logger.info("سرور متوقف شد")

# سرویس سیستمی برای اجرای خودکار
class ConfigServerService:
    def __init__(self):
        self.server = ConfigServer()
        
    def setup_service(self):
        """تنظیم سرویس سیستمی"""
        service_path = '/etc/systemd/system/v2ray_config_server.service'
        
        service_content = """[Unit]
Description=V2Ray Config Server
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/v2ray_config_server.py
Restart=always
User=root
Group=root
Environment=PATH=/usr/bin:/usr/local/bin
WorkingDirectory=/tmp

[Install]
WantedBy=multi-user.target
"""

        try:
            # نوشتن فایل سرویس
            with open(service_path, 'w') as f:
                f.write(service_content)
            
            # کپی خود این اسکریپت به مسیر اجرایی سیستمی
            current_script = os.path.abspath(__file__)
            target_path = '/usr/local/bin/v2ray_config_server.py'
            
            with open(current_script, 'r') as src, open(target_path, 'w') as dst:
                dst.write(src.read())
            
            # تنظیم دسترسی‌ها
            os.chmod(target_path, 0o755)
            
            # فعال‌سازی و شروع سرویس
            subprocess.run(['systemctl', 'daemon-reload'], check=True)
            subprocess.run(['systemctl', 'enable', 'v2ray_config_server'], check=True)
            subprocess.run(['systemctl', 'start', 'v2ray_config_server'], check=True)
            
            logger.info("سرویس سیستمی با موفقیت نصب و راه‌اندازی شد")
            
        except Exception as e:
            logger.error(f"خطا در تنظیم سرویس سیستمی: {e}")
    
    def run(self):
        """اجرای سرور"""
        # تنظیم سیگنال‌ها برای خروج تمیز
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        
        self.server.start()
    
    def signal_handler(self, sig, frame):
        """مدیریت سیگنال‌های خروج"""
        logger.info(f"سیگنال {sig} دریافت شد. در حال خروج...")
        self.server.stop()
        sys.exit(0)

# نقطه ورودی اصلی برنامه
if __name__ == "__main__":
    # بررسی حقوق دسترسی (باید با دسترسی root اجرا شود)
    if os.geteuid() != 0:
        print("این برنامه نیاز به دسترسی root دارد. لطفاً با sudo اجرا کنید.")
        sys.exit(1)
    
    # بررسی آرگومان‌های خط فرمان
    if len(sys.argv) > 1:
        if sys.argv[1] == "install":
            # نصب به عنوان سرویس سیستمی
            service = ConfigServerService()
            service.setup_service()
            sys.exit(0)
        elif sys.argv[1] == "uninstall":
            # حذف سرویس سیستمی
            try:
                subprocess.run(['systemctl', 'stop', 'v2ray_config_server'], check=False)
                subprocess.run(['systemctl', 'disable', 'v2ray_config_server'], check=False)
                os.remove('/etc/systemd/system/v2ray_config_server.service')
                subprocess.run(['systemctl', 'daemon-reload'], check=False)
                print("سرویس با موفقیت حذف شد.")
            except Exception as e:
                print(f"خطا در حذف سرویس: {e}")
            sys.exit(0)
    
    # اجرای عادی برنامه
    service = ConfigServerService()
    service.run()
EOF
    
    # جایگزینی WHITELIST_PLACEHOLDER با لیست واقعی
    sed -i "s/WHITELIST_PLACEHOLDER/$WHITELIST/g" v2ray_config_server.py
    
    # تنظیم دسترسی‌ها
    chmod +x v2ray_config_server.py
    
    echo -e "${GREEN}[موفقیت] اسکریپت پایتون با موفقیت ایجاد شد${NC}"
}

# نصب و راه‌اندازی سرویس
install_service() {
    echo -e "${YELLOW}[اطلاعات] در حال نصب سرویس...${NC}"
    
    # کپی اسکریپت به مسیر سیستمی
    cp v2ray_config_server.py /usr/local/bin/
    chmod +x /usr/local/bin/v2ray_config_server.py
    
    # ایجاد فایل سرویس
    cat > /etc/systemd/system/v2ray_config_server.service << EOF
[Unit]
Description=V2Ray Config Server
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/v2ray_config_server.py
Restart=always
User=root
Group=root
Environment=PATH=/usr/bin:/usr/local/bin
WorkingDirectory=/tmp

[Install]
WantedBy=multi-user.target
EOF
    
    # فعال‌سازی و شروع سرویس
    systemctl daemon-reload
    systemctl enable v2ray_config_server
    systemctl start v2ray_config_server
    
    echo -e "${GREEN}[موفقیت] سرویس با موفقیت نصب و راه‌اندازی شد${NC}"
}

# تنظیم فایروال
setup_firewall() {
    echo -e "${YELLOW}[اطلاعات] در حال تنظیم فایروال...${NC}"
    
    # باز کردن پورت 800 برای دسترسی به API
    iptables -A INPUT -p tcp --dport 800 -j ACCEPT
    
    # ذخیره تنظیمات فایروال
    if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
        apt install -y iptables-persistent
        netfilter-persistent save
    elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
        service iptables save
    fi
    
    echo -e "${GREEN}[موفقیت] فایروال با موفقیت تنظیم شد${NC}"
}

# نمایش اطلاعات نهایی
show_info() {
    # دریافت آی‌پی سرور
    SERVER_IP=$(curl -s ifconfig.me)
    
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${GREEN}نصب و راه‌اندازی سرور کانفیگ V2Ray با موفقیت انجام شد!${NC}"
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${YELLOW}اطلاعات سرور:${NC}"
    echo -e "آی‌پی سرور: ${GREEN}$SERVER_IP${NC}"
    echo -e "پورت سرور: ${GREEN}800${NC}"
    echo -e "آدرس API: ${GREEN}http://$SERVER_IP:800/api/configs${NC}"
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${YELLOW}دستورات مدیریتی:${NC}"
    echo -e "وضعیت سرویس: ${GREEN}systemctl status v2ray_config_server${NC}"
    echo -e "راه‌اندازی مجدد: ${GREEN}systemctl restart v2ray_config_server${NC}"
    echo -e "مشاهده لاگ‌ها: ${GREEN}journalctl -u v2ray_config_server${NC}"
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${PURPLE}آی‌پی‌های مجاز شده:${NC}"
    echo -e "${GREEN}$WHITELIST${NC}"
    echo -e "${BLUE}===================================================================${NC}"
}

# اجرای اصلی برنامه
main() {
    check_os
    install_dependencies
    setup_whitelist
    create_python_script
    install_service
    setup_firewall
    show_info
}

# اجرای برنامه
main
