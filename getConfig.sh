#!/bin/bash

# رنگ‌ها برای بهبود خوانایی خروجی
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # بدون رنگ

echo -e "${BLUE}=== شروع نصب اتوماتیک XUI Secure Manager ===${NC}"

# بررسی اجرا با دسترسی روت
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}این اسکریپت باید با دسترسی روت اجرا شود. لطفا با sudo اجرا کنید.${NC}"
    exit 1
fi

# بررسی سیستم‌عامل
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${YELLOW}سیستم‌عامل قابل شناسایی نیست. فرض می‌شود Debian/Ubuntu است.${NC}"
    OS="debian"
fi

# نصب iptables-persistent برای ذخیره دائمی قوانین فایروال
echo -e "${YELLOW}در حال نصب iptables-persistent برای مدیریت فایروال...${NC}"
if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ]; then
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    apt-get update
    apt-get install -y iptables-persistent
elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ] || [ "$OS" == "fedora" ]; then
    yum install -y iptables-services
    systemctl enable iptables
    systemctl start iptables
fi

# تنظیم اولیه فایروال
echo -e "${YELLOW}در حال تنظیم قوانین اولیه فایروال...${NC}"

# ذخیره قوانین iptables در یک فایل اختصاصی
create_firewall_script() {
    local FIREWALL_SCRIPT="/usr/local/bin/xui-firewall.sh"
    
    cat > $FIREWALL_SCRIPT << 'EOL'
#!/bin/bash

# رنگ‌ها برای بهبود خوانایی خروجی
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # بدون رنگ

# مسیر فایل لاگ
LOG_FILE="/var/log/xui-firewall.log"

# تابع ثبت لاگ
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
    echo -e "$1"
}

# پاک کردن قوانین موجود
reset_iptables() {
    log_message "${YELLOW}پاک کردن قوانین موجود iptables...${NC}"
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
}

# تنظیم قوانین پایه
setup_base_rules() {
    log_message "${YELLOW}تنظیم قوانین پایه فایروال...${NC}"
    
    # اجازه ارتباطات لوکال
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # اجازه ارتباطات برقرار شده و مرتبط
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # اجازه پینگ (اختیاری)
    iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
    
    # اجازه SSH (پورت 22)
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    
    # اجازه HTTP و HTTPS (پورت 80 و 443)
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    
    # اجازه پورت XUI Manager (8008)
    iptables -A INPUT -p tcp --dport 8008 -j ACCEPT
    
    # اجازه پورت XUI Panel (نمونه: پورت XUI شما)
    # اگر پورت پنل شما متفاوت است، این مقدار را تغییر دهید
    iptables -A INPUT -p tcp --dport 54321 -j ACCEPT
    
    # بستن بقیه ارتباطات ورودی
    iptables -P INPUT DROP
}

# اضافه کردن IP به لیست سفید
add_ip_to_whitelist() {
    local IP=$1
    local COMMENT=$2
    
    # بررسی اعتبار IP
    if [[ ! $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_message "${RED}آدرس IP نامعتبر: $IP${NC}"
        return 1
    fi
    
    # بررسی وجود IP در لیست سفید
    if iptables -C INPUT -s $IP -j ACCEPT 2>/dev/null; then
        log_message "${YELLOW}آدرس IP $IP از قبل در لیست سفید وجود دارد.${NC}"
        return 0
    fi
    
    # اضافه کردن IP به لیست سفید
    if [ -z "$COMMENT" ]; then
        COMMENT="Added on $(date '+%Y-%m-%d')"
    fi
    
    iptables -I INPUT -s $IP -m comment --comment "$COMMENT" -j ACCEPT
    log_message "${GREEN}آدرس IP $IP به لیست سفید اضافه شد.${NC}"
    
    # ذخیره قوانین
    save_rules
    
    return 0
}

# حذف IP از لیست سفید
remove_ip_from_whitelist() {
    local IP=$1
    
    # بررسی وجود IP در لیست سفید
    if ! iptables -C INPUT -s $IP -j ACCEPT 2>/dev/null; then
        log_message "${YELLOW}آدرس IP $IP در لیست سفید وجود ندارد.${NC}"
        return 1
    fi
    
    # حذف IP از لیست سفید
    iptables -D INPUT -s $IP -j ACCEPT
    log_message "${GREEN}آدرس IP $IP از لیست سفید حذف شد.${NC}"
    
    # ذخیره قوانین
    save_rules
    
    return 0
}

# ذخیره قوانین
save_rules() {
    log_message "${YELLOW}ذخیره قوانین فایروال...${NC}"
    
    if [ -x "$(which netfilter-persistent)" ]; then
        netfilter-persistent save
    elif [ -x "$(which iptables-save)" ]; then
        if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ]; then
            iptables-save > /etc/iptables/rules.v4
        elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ] || [ "$OS" == "fedora" ]; then
            iptables-save > /etc/sysconfig/iptables
        fi
    else
        log_message "${RED}ابزار ذخیره قوانین iptables یافت نشد!${NC}"
        return 1
    fi
    
    log_message "${GREEN}قوانین فایروال با موفقیت ذخیره شدند.${NC}"
    return 0
}

# نمایش لیست IP های سفید
list_whitelisted_ips() {
    log_message "${YELLOW}لیست IP های موجود در لیست سفید:${NC}"
    iptables -L INPUT -n | grep -E "ACCEPT.*([0-9]{1,3}\.){3}[0-9]{1,3}"
}

# بررسی وضعیت فایروال
check_firewall_status() {
    log_message "${YELLOW}وضعیت فعلی فایروال:${NC}"
    iptables -L -n -v
}

# پردازش پارامترهای ورودی
case "$1" in
    --reset)
        reset_iptables
        log_message "${GREEN}تمام قوانین فایروال پاک شدند.${NC}"
        ;;
    --setup)
        reset_iptables
        setup_base_rules
        save_rules
        log_message "${GREEN}قوانین پایه فایروال با موفقیت تنظیم شدند.${NC}"
        ;;
    --add)
        if [ -z "$2" ]; then
            log_message "${RED}خطا: آدرس IP را وارد کنید.${NC}"
            echo "مثال: $0 --add 192.168.1.1 [توضیحات اختیاری]"
            exit 1
        fi
        add_ip_to_whitelist "$2" "$3"
        ;;
    --remove)
        if [ -z "$2" ]; then
            log_message "${RED}خطا: آدرس IP را وارد کنید.${NC}"
            echo "مثال: $0 --remove 192.168.1.1"
            exit 1
        fi
        remove_ip_from_whitelist "$2"
        ;;
    --list)
        list_whitelisted_ips
        ;;
    --status)
        check_firewall_status
        ;;
    --help|*)
        echo "استفاده از اسکریپت:"
        echo "  $0 --reset                      : پاک کردن تمام قوانین فایروال"
        echo "  $0 --setup                      : تنظیم قوانین پایه فایروال"
        echo "  $0 --add IP [توضیحات]           : اضافه کردن IP به لیست سفید"
        echo "  $0 --remove IP                  : حذف IP از لیست سفید"
        echo "  $0 --list                       : نمایش لیست IP های سفید"
        echo "  $0 --status                     : بررسی وضعیت فایروال"
        echo "  $0 --help                       : نمایش این راهنما"
        ;;
esac

exit 0
EOL

    chmod +x $FIREWALL_SCRIPT
    echo -e "${GREEN}اسکریپت فایروال در مسیر $FIREWALL_SCRIPT ایجاد شد.${NC}"
}

# ایجاد اسکریپت فایروال
create_firewall_script

# تنظیم اولیه فایروال
/usr/local/bin/xui-firewall.sh --setup

# بررسی و نصب پکیج‌های پایه
echo -e "${YELLOW}در حال بررسی و نصب پکیج‌های پایه...${NC}"

if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ]; then
    apt update -y
    apt install -y python3 python3-pip curl wget git
elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ] || [ "$OS" == "fedora" ]; then
    yum update -y
    yum install -y python3 python3-pip curl wget git
elif [ "$OS" == "alpine" ]; then
    apk update
    apk add python3 py3-pip curl wget git
else
    echo -e "${YELLOW}سیستم‌عامل پشتیبانی نشده. در حال تلاش برای استفاده از دستورات عمومی...${NC}"
    # تلاش برای استفاده از پکیج‌منیجر‌های معمول
    which apt && apt update -y && apt install -y python3 python3-pip curl wget git
    which yum && yum update -y && yum install -y python3 python3-pip curl wget git
    which apk && apk update && apk add python3 py3-pip curl wget git
fi

echo -e "${GREEN}نصب پکیج‌های پایه به پایان رسید.${NC}"

# بررسی نصب Python
echo -e "${YELLOW}در حال بررسی نصب Python...${NC}"
if command -v python3 &>/dev/null; then
    echo -e "${GREEN}Python نصب شده است:${NC}"
    python3 --version
else
    echo -e "${YELLOW}Python یافت نشد. در حال تلاش برای نصب...${NC}"
    if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ]; then
        apt install -y python3
    elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ] || [ "$OS" == "fedora" ]; then
        yum install -y python3
    elif [ "$OS" == "alpine" ]; then
        apk add python3
    fi
    
    if command -v python3 &>/dev/null; then
        echo -e "${GREEN}Python با موفقیت نصب شد:${NC}"
        python3 --version
    else
        echo -e "${YELLOW}نصب Python با شکست مواجه شد. لطفا به صورت دستی نصب کنید.${NC}"
        exit 1
    fi
fi

# بررسی نصب pip
echo -e "${YELLOW}در حال بررسی نصب pip...${NC}"
if command -v pip3 &>/dev/null; then
    echo -e "${GREEN}pip نصب شده است:${NC}"
    pip3 --version
else
    echo -e "${YELLOW}pip یافت نشد. در حال تلاش برای نصب...${NC}"
    # تلاش برای نصب pip
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    python3 get-pip.py
    rm get-pip.py
    
    if command -v pip3 &>/dev/null; then
        echo -e "${GREEN}pip با موفقیت نصب شد:${NC}"
        pip3 --version
    else
        echo -e "${YELLOW}نصب pip با شکست مواجه شد. در حال تلاش با روش دیگر...${NC}"
        if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ]; then
            apt install -y python3-pip
        elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ] || [ "$OS" == "fedora" ]; then
            yum install -y python3-pip
        elif [ "$OS" == "alpine" ]; then
            apk add py3-pip
        fi
        
        if command -v pip3 &>/dev/null; then
            echo -e "${GREEN}pip با موفقیت نصب شد:${NC}"
            pip3 --version
        else
            echo -e "${YELLOW}نصب pip با شکست مواجه شد. لطفا به صورت دستی نصب کنید.${NC}"
            exit 1
        fi
    fi
fi

# نصب وابستگی‌های مورد نیاز با pip
echo -e "${YELLOW}در حال نصب وابستگی‌های پایتون...${NC}"
pip3 install requests flask urllib3

# ذخیره اسکریپت اصلی با تغییرات امنیتی
echo -e "${YELLOW}در حال آماده‌سازی فایل اصلی با قابلیت‌های امنیتی...${NC}"
cat > xui_manager.py << 'EOF'
#!/usr/bin/env python3
import requests
import json
import urllib.parse
import re
import socket
import subprocess
import urllib3
import random
import os
import time
import logging
from flask import Flask, jsonify, request, Response

# تنظیم لاگینگ
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/xui-manager.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('xui_manager')

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class IPSecurityManager:
    """مدیریت امنیت IP و کنترل دسترسی"""
    
    def __init__(self):
        self.whitelist_ips = {}
        self.firewall_script = "/usr/local/bin/xui-firewall.sh"
        self.allowed_requests_limit = 5  # تعداد درخواست‌های مجاز قبل از اضافه شدن به لیست سفید
        self.request_counter = {}  # شمارنده درخواست‌ها برای هر IP
        self.last_cleanup = time.time()
        
    def add_to_whitelist(self, ip, reason="Auto-added by XUI Manager"):
        """اضافه کردن IP به لیست سفید فایروال"""
        try:
            if ip in self.whitelist_ips:
                logger.info(f"IP {ip} is already in whitelist.")
                return True
                
            logger.info(f"Adding IP {ip} to whitelist. Reason: {reason}")
            
            cmd = [self.firewall_script, "--add", ip, reason]
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info(f"Successfully added IP {ip} to whitelist.")
                self.whitelist_ips[ip] = {
                    'added_at': time.time(),
                    'reason': reason
                }
                return True
            else:
                logger.error(f"Failed to add IP {ip} to whitelist: {result.stderr}")
                return False
        except Exception as e:
            logger.error(f"Error adding IP {ip} to whitelist: {str(e)}")
            return False
            
    def is_whitelisted(self, ip):
        """بررسی اینکه آیا IP در لیست سفید است"""
        # اول بررسی کش داخلی
        if ip in self.whitelist_ips:
            return True
            
        # سپس بررسی فایروال
        try:
            cmd = ["iptables", "-C", "INPUT", "-s", ip, "-j", "ACCEPT"]
            result = subprocess.run(cmd, capture_output=True, text=True)
            return result.returncode == 0
        except Exception as e:
            logger.error(f"Error checking whitelist status for IP {ip}: {str(e)}")
            return False
            
    def track_request(self, ip):
        """پیگیری درخواست‌های IP و افزودن به لیست سفید در صورت نیاز"""
        # پاکسازی کش هر ساعت
        current_time = time.time()
        if current_time - self.last_cleanup > 3600:  # یک ساعت
            self.cleanup_old_data()
            self.last_cleanup = current_time
        
        # IP های خاص را همیشه قبول کن
        if ip == "127.0.0.1" or ip == "::1" or ip.startswith("192.168.") or ip.startswith("10."):
            return True
            
        # اگر در لیست سفید است، قبول کن
        if self.is_whitelisted(ip):
            return True
            
        # افزایش شمارنده درخواست‌ها
        if ip not in self.request_counter:
            self.request_counter[ip] = {
                'count': 1,
                'first_seen': time.time()
            }
        else:
            self.request_counter[ip]['count'] += 1
            
        # اگر تعداد درخواست‌ها از حد مجاز بیشتر شد، به لیست سفید اضافه کن
        if self.request_counter[ip]['count'] >= self.allowed_requests_limit:
            self.add_to_whitelist(ip, "Automatically added after multiple legitimate requests")
            return True
            
        return True  # همیشه اجازه دسترسی بده اما فقط IPs معتبر را به لیست سفید اضافه کن
        
    def cleanup_old_data(self):
        """پاکسازی داده‌های قدیمی از کش"""
        current_time = time.time()
        expired_time = current_time - 86400  # 24 ساعت
        
        # پاکسازی شمارنده‌های قدیمی
        for ip in list(self.request_counter.keys()):
            if self.request_counter[ip]['first_seen'] < expired_time:
                del self.request_counter[ip]
                
        logger.info(f"Cleaned up old data. Current tracked IPs: {len(self.request_counter)}")

class XuiManager:
    def __init__(self):
        # Fixed credentials
        self.username = "zahed"
        self.password = "zahed2341"
        self.port = 80
        self.ssl = False
        self.server_ip = "127.0.0.1"  # Initially set to localhost, will be updated later
        self.cookie = self.login_and_get_cookie()
        
    def login_and_get_cookie(self):
        """Login to 3x-ui panel and get authentication cookie"""
        protocol = "https" if self.ssl else "http"
        url = f"{protocol}://{self.server_ip}:{self.port}/login"
        
        try:
            logger.info(f"Attempting to login to {url}")
            
            # Using data parameter with dictionary for form data
            data = {
                'username': self.username,
                'password': self.password
            }
            
            # Set proper headers
            headers = {
                'Content-Type': 'application/x-www-form-urlencoded'
            }
            
            response = requests.post(
                url,
                data=data,
                headers=headers,
                timeout=(10, 30),
                verify=False
            )
            
            logger.info(f"Login response status: {response.status_code}")
            
            # Extract cookies from response
            cookies = response.cookies
            for cookie in cookies:
                logger.info(f"Found cookie: {cookie.name} = {cookie.value}")
                if cookie.name in ['3x-ui', 'session', 'token']:
                    return cookie.value
            
            # Try to extract from cookie header if not found in cookies object
            cookie_header = response.headers.get('Set-Cookie')
            if cookie_header:
                logger.info(f"Cookie header found: {cookie_header[:100]}...")
                
                # Try to extract various possible cookie names
                for cookie_name in ['3x-ui', 'session', 'token']:
                    match = re.search(f'{cookie_name}=([^;]*)', cookie_header)
                    if match:
                        cookie_value = match.group(1)
                        logger.info(f"Extracted {cookie_name} cookie: {cookie_value[:10]}...")
                        return cookie_value
            
            logger.warning("No authentication cookie found in response")
            return None
        except Exception as e:
            logger.error(f"Login error: {str(e)}")
            return None
            
    def fetch_inbounds_list(self, config_type="app"):
        """Fetch inbounds list from 3x-ui panel"""
        if not self.cookie:
            return json.dumps({'status': 'error', 'message': 'Authentication failed - no cookie available'})
            
        # Try multiple possible API endpoints to find inbounds
        endpoints = [
            "/panel/api/inbounds/list",
            "/api/inbounds/list",                    
            "/xui/API/inbounds/list",                
            "/xui/inbounds/list",                  
            "/panel/inbounds/list"                 
        ]
        
        protocol = "https" if self.ssl else "http"
        
        for endpoint in endpoints:
            url = f"{protocol}://{self.server_ip}:{self.port}{endpoint}"
            
            try:
                logger.info(f"Trying to fetch inbounds from {url}")
                
                # Try with different cookie formats
                headers_variations = [
                    {'Accept': 'application/json', 'Cookie': f'3x-ui={self.cookie}'},
                    {'Accept': 'application/json', 'Cookie': f'session={self.cookie}'},
                    {'Accept': 'application/json', 'Cookie': f'token={self.cookie}'},
                    {'Accept': 'application/json', 'Authorization': f'Bearer {self.cookie}'}
                ]
                
                for headers in headers_variations:
                    response = requests.get(
                        url,
                        headers=headers,
                        timeout=(10, 30),
                        verify=False
                    )
                    
                    if response.status_code == 200 and response.text:
                        logger.info(f"Successful response from {endpoint} with headers {headers}")
                        
                        # Check if the response looks like valid JSON with inbounds data
                        try:
                            data = response.json()
                            # Look for common keys that would indicate inbound data
                            if 'obj' in data or 'inbounds' in data or 'data' in data:
                                return self.generate_custom_format(response.text, data, config_type)
                        except json.JSONDecodeError:
                            logger.warning(f"Response is not valid JSON from {endpoint}")
                            continue
            except Exception as e:
                logger.error(f"Error fetching from {endpoint}: {str(e)}")
                continue
        
        return json.dumps({'status': 'error', 'message': 'Could not fetch inbounds from any known endpoint'})
            
    def generate_custom_format(self, json_response, parsed_data=None, config_type="app"):
        """Generate custom format configs from inbounds response"""
        try:
            # Use already parsed data if provided, otherwise parse the JSON
            response = parsed_data if parsed_data else json.loads(json_response)
            configs = []
            
            # Handle various response formats from different panel versions
            inbounds = []
            
            # Standard 3x-ui format
            if 'obj' in response:
                inbounds = response['obj']
            # Alternative format
            elif 'inbounds' in response:
                inbounds = response['inbounds']
            # Sanaei specific format
            elif 'data' in response:
                inbounds = response['data']
            # Direct array format
            elif isinstance(response, list):
                inbounds = response
                
            if not inbounds:
                logger.warning("No inbounds found in response")
                return json.dumps({
                    'status': 'error', 
                    'message': 'No inbounds found in response'
                })
                
            logger.info(f"Found {len(inbounds)} inbounds")
            
            for inbound in inbounds:
                inbound_id = inbound.get('id', 'unknown')
                logger.info(f"Processing inbound: {inbound_id}")
                
                # Parse the settings and stream settings - handle both string and object formats
                settings = inbound.get('settings', {})
                if isinstance(settings, str):
                    try:
                        settings = json.loads(settings)
                    except json.JSONDecodeError:
                        logger.error(f"Error parsing settings for inbound {inbound_id}")
                        continue
                        
                stream_settings = inbound.get('streamSettings', {})
                if isinstance(stream_settings, str):
                    try:
                        stream_settings = json.loads(stream_settings)
                    except json.JSONDecodeError:
                        logger.error(f"Error parsing streamSettings for inbound {inbound_id}")
                        continue
                
                # Look for clients in different possible locations
                clients = []
                
                # Standard location
                if 'clients' in settings:
                    clients = settings['clients']
                # Alternative location
                elif 'client' in settings:
                    clients = [settings['client']]
                # Check for Trojan format
                elif 'users' in settings:
                    clients = settings['users']
                
                if not clients:
                    logger.warning(f"No clients found for inbound {inbound_id}")
                    continue
                
                logger.info(f"Found {len(clients)} clients for inbound {inbound_id}")
                    
                for client in clients:
                    config = self.build_custom_config(client, inbound, stream_settings, config_type)
                    if config:
                        configs.append(config)
                        
            # Create the custom format response
            result = {
                "status": "success",
                "configs": configs
            }
            #return json.dumps(result)
            return "b8VNdLk4VnreN4vMYlzDFCU1RzwZgOZqdE0LtmBtM6S+xtxNmJvXc12cCDfx31I="
            
        except Exception as e:
            logger.error(f"Error generating configs: {str(e)}")
            import traceback
            traceback.print_exc()
            return json.dumps({'status': 'error', 'message': f'Error generating configs: {str(e)}'})
            
    def build_custom_config(self, client, inbound, stream_settings, config_type="app"):
        """Build custom format config for a client"""
        try:
            client_id = client.get('id', client.get('password', ''))
            client_email = client.get('email', 'unknown')
            
            logger.info(f"Building config for client: {client_email}")
            
            if not client_id:
                logger.warning(f"No valid ID found for client {client_email}")
                return None
            
            # Build the VLESS config string
            vless_config = self.build_vless_config(client, inbound, stream_settings)
            if not vless_config:
                return None
                
            # Use the provided config_type directly 
            usage_type = config_type
                
            # Generate random number for name
            random_num1 = random.randint(1000, 9999)
            random_num2 = random.randint(1000000, 9999999)
            
            # Create custom format object
            custom_config = {
                "name": f"A {random_num2}",
                "country": "us",
                "config_type": "config",
                "usage_type": usage_type,
                "config_data": vless_config,
                "is_active": True
            }
            
            return custom_config
        except Exception as e:
            logger.error(f"Error building custom config: {str(e)}")
            return None
            
    def build_vless_config(self, client, inbound, stream_settings):
        """Build VLESS config string"""
        try:
            client_id = client.get('id', client.get('password', ''))
            
            config = f"vless://{client_id}@{self.server_ip}:{inbound['port']}?"
            params = {'type': stream_settings.get('network', 'tcp')}
            
            self.handle_security_settings(stream_settings, params)
            
            # Always add encryption=none for VLESS
            params['encryption'] = 'none'
            
            query_string = urllib.parse.urlencode(params)
            remark = "VPN APP"  # Fixed remark as requested
            
            return f"{config}{query_string}#{remark}"
        except Exception as e:
            logger.error(f"Error building VLESS config: {str(e)}")
            return None
            
    def handle_security_settings(self, stream_settings, params):
        """Process security settings"""
        security = stream_settings.get('security', 'none')
        logger.info(f"Security type: {security}")
        
        if security == 'none':
            self.handle_none_security(stream_settings, params)
        elif security == 'reality':
            self.handle_reality_security(stream_settings, params)
        elif security == 'tls':
            self.handle_tls_security(stream_settings, params)
            
    def handle_none_security(self, stream_settings, params):
        """Process 'none' security settings"""
        network = stream_settings.get('network', 'tcp')
        params['security'] = 'none'
        
        if network == 'tcp':
            tcp_settings = stream_settings.get('tcpSettings', {})
            header_type = tcp_settings.get('header', {}).get('type', '')
            
            if header_type == 'http':
                headers = tcp_settings.get('header', {}).get('request', {}).get('headers', {})
                params['path'] = '/'
                if 'Host' in headers and headers['Host']:
                    if isinstance(headers['Host'], list) and headers['Host']:
                        params['host'] = headers['Host'][0]
                    else:
                        params['host'] = headers['Host']
                params['headerType'] = 'http'
        
        elif network == 'ws':
            ws_settings = stream_settings.get('wsSettings', {})
            params['path'] = ws_settings.get('path', '/')
            
            if 'headers' in ws_settings and 'Host' in ws_settings['headers']:
                params['host'] = ws_settings['headers']['Host']
                
        elif network == 'grpc':
            grpc_settings = stream_settings.get('grpcSettings', {})
            params['serviceName'] = grpc_settings.get('serviceName', '')
            
    def handle_tls_security(self, stream_settings, params):
        """Process 'tls' security settings"""
        params['security'] = 'tls'
        
        tls_settings = stream_settings.get('tlsSettings', {})
        server_name = tls_settings.get('serverName', '')
        if server_name:
            params['sni'] = server_name
            
        # Process network specific settings
        network = stream_settings.get('network', 'tcp')
        if network == 'ws':
            ws_settings = stream_settings.get('wsSettings', {})
            params['path'] = ws_settings.get('path', '/')
            
            if 'headers' in ws_settings and 'Host' in ws_settings['headers']:
                params['host'] = ws_settings['headers']['Host']
                
        elif network == 'grpc':
            grpc_settings = stream_settings.get('grpcSettings', {})
            params['serviceName'] = grpc_settings.get('serviceName', '')
            
    def handle_reality_security(self, stream_settings, params):
        """Process 'reality' security settings"""
        params['security'] = 'reality'
        
        reality_settings = stream_settings.get('realitySettings', {})
        settings = reality_settings.get('settings', {})
        
        # Try different possible locations for publicKey
        if 'publicKey' in settings:
            params['pbk'] = settings.get('publicKey', '')
        elif 'publicKey' in reality_settings:
            params['pbk'] = reality_settings.get('publicKey', '')
            
        # Try different possible locations for fingerprint
        if 'fingerprint' in settings:
            params['fp'] = settings.get('fingerprint', '')
        elif 'fingerprint' in reality_settings:
            params['fp'] = reality_settings.get('fingerprint', '')
        
        # Try different possible locations for serverNames
        server_names = []
        if 'serverNames' in reality_settings and reality_settings['serverNames']:
            server_names = reality_settings['serverNames']
        elif 'serverName' in reality_settings:
            server_names = [reality_settings['serverName']]
            
        if server_names:
            params['sni'] = server_names[0]
            
        # Try different possible locations for shortIds
        short_ids = []
        if 'shortIds' in reality_settings and reality_settings['shortIds']:
            short_ids = reality_settings['shortIds']
        elif 'shortId' in reality_settings:
            short_ids = [reality_settings['shortId']]
            
        if short_ids:
            params['sid'] = short_ids[0]
        
        # Try different possible locations for spiderX
        if 'spiderX' in settings:
            params['spx'] = settings.get('spiderX', '')
        elif 'spiderX' in reality_settings:
            params['spx'] = reality_settings.get('spiderX', '')

# Function to get local IP
def get_local_ip():
    try:
        # First attempt: try to get IP via socket connection
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))  # Connect to Google DNS
        local_ip = s.getsockname()[0]
        s.close()
        logger.info(f"Local IP detected via socket: {local_ip}")
        return local_ip
    except Exception as e:
        logger.error(f"Socket method failed: {str(e)}")
        try:
            # Second attempt: try to get IP from hostname
            result = subprocess.run(['hostname', '-I'], stdout=subprocess.PIPE)
            ip = result.stdout.decode('utf-8').strip().split()[0]
            if ip:
                logger.info(f"Local IP detected via hostname: {ip}")
                return ip
        except Exception as e:
            logger.error(f"Hostname method failed: {str(e)}")
        
        # Fallback to localhost if all methods fail
        logger.warning("Falling back to localhost (127.0.0.1)")
        return "127.0.0.1"

# Flask server with security middleware
app = Flask(__name__)
security_manager = IPSecurityManager()

@app.before_request
def security_check():
    """میان‌افزار امنیتی برای بررسی IP قبل از هر درخواست"""
    client_ip = request.remote_addr
    logger.info(f"Request from IP: {client_ip} to {request.path}")
    
    # بررسی و ثبت IP
    if security_manager.track_request(client_ip):
        # اجازه دسترسی داده شده
        return None
    else:
        # رد درخواست
        logger.warning(f"Access denied for IP: {client_ip}")
        return Response("Access Denied", status=403)

@app.route('/')
def home():
    return """
    <html>
    <head><title>XUI Secure Manager</title></head>
    <body>
        <h1>XUI Secure Manager server is running</h1>
        <p>Use <a href="/app/configs">/app/configs</a> for app configurations.</p>
        <p>Use <a href="/ads/configs">/ads/configs</a> for ads configurations.</p>
    </body>
    </html>
    """

@app.route('/app/configs')
def get_app_configs():
    """Get configurations for app usage"""
    try:
        client_ip = request.remote_addr
        local_ip = get_local_ip()
        logger.info(f"Using local IP: {local_ip}")
        
        xui_manager = XuiManager()
        # Set the server IP to local IP for the config URLs
        xui_manager.server_ip = local_ip
        
        if not xui_manager.cookie:
            return jsonify({
                'status': 'error', 
                'message': 'Failed to authenticate with 3x-ui panel'
            })
            
        response_text = xui_manager.fetch_inbounds_list(config_type="app")
        response_json = json.loads(response_text)
        
        # اضافه کردن IP کاربر به لیست سفید بعد از دریافت موفق کانفیگ‌ها
        if response_json.get('status') == 'success':
            security_manager.add_to_whitelist(client_ip, "Successfully fetched app configs")
            
        return jsonify(response_json)
    except Exception as e:
        import traceback
        traceback.print_exc()
        logger.error(f"Error in get_app_configs: {str(e)}")
        return jsonify({'status': 'error', 'message': f'Server error: {str(e)}'})

@app.route('/ads/configs')
def get_ads_configs():
    """Get configurations for ads usage"""
    try:
        client_ip = request.remote_addr
        local_ip = get_local_ip()
        logger.info(f"Using local IP: {local_ip}")
        
        xui_manager = XuiManager()
        # Set the server IP to local IP for the config URLs
        xui_manager.server_ip = local_ip
        
        if not xui_manager.cookie:
            return jsonify({
                'status': 'error', 
                'message': 'Failed to authenticate with 3x-ui panel'
            })
            
        response_text = xui_manager.fetch_inbounds_list(config_type="ads")
        response_json = json.loads(response_text)
        
        # اضافه کردن IP کاربر به لیست سفید بعد از دریافت موفق کانفیگ‌ها
        if response_json.get('status') == 'success':
            security_manager.add_to_whitelist(client_ip, "Successfully fetched ads configs")
            
        return jsonify(response_json)
    except Exception as e:
        import traceback
        traceback.print_exc()
        logger.error(f"Error in get_ads_configs: {str(e)}")
        return jsonify({'status': 'error', 'message': f'Server error: {str(e)}'})

# Backwards compatibility
@app.route('/configs')
def get_configs():
    """Default configs endpoint (uses app type)"""
    return get_app_configs()

@app.route('/security/whitelist')
def whitelist_info():
    """نمایش اطلاعات لیست سفید برای مدیر سیستم"""
    # فقط به localhost اجازه دسترسی بده
    if request.remote_addr != '127.0.0.1' and request.remote_addr != '::1':
        return jsonify({'status': 'error', 'message': 'Access denied'})
        
    try:
        cmd = [security_manager.firewall_script, "--list"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        return jsonify({
            'status': 'success',
            'whitelist': result.stdout,
            'tracked_ips': len(security_manager.request_counter)
        })
    except Exception as e:
        logger.error(f"Error getting whitelist info: {str(e)}")
        return jsonify({'status': 'error', 'message': f'Error: {str(e)}'})

if __name__ == '__main__':
    logger.info("Starting XUI Secure Manager server on port 8008...")
    # اطمینان از وجود مسیر فایل لاگ
    os.makedirs(os.path.dirname('/var/log/xui-manager.log'), exist_ok=True)
    app.run(host='0.0.0.0', port=8008, debug=False)
EOF

# تغییر مجوز اجرایی فایل
chmod +x xui_manager.py

# ایجاد فایل سرویس systemd برای اجرای خودکار در هنگام بوت
echo -e "${YELLOW}در حال ایجاد سرویس سیستمی برای اجرای خودکار...${NC}"

SERVICE_PATH="/etc/systemd/system/xui-manager.service"

cat > $SERVICE_PATH << EOF
[Unit]
Description=XUI Secure Manager Service
After=network.target

[Service]
User=root
WorkingDirectory=$(pwd)
ExecStart=$(which python3) $(pwd)/xui_manager.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# فعال‌سازی و شروع سرویس
echo -e "${YELLOW}در حال فعال‌سازی و شروع سرویس...${NC}"
systemctl daemon-reload
systemctl enable xui-manager.service
systemctl start xui-manager.service

# نمایش اطلاعات نهایی
SERVER_IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
echo -e "${GREEN}=== نصب XUI Secure Manager به پایان رسید ===${NC}"
echo -e "${GREEN}سرویس با موفقیت راه‌اندازی شد و به صورت خودکار در هنگام بوت اجرا خواهد شد.${NC}"
echo -e "${BLUE}آدرس دسترسی:${NC}"
echo -e "  http://${SERVER_IP}:8008 - صفحه اصلی"
echo -e "  http://${SERVER_IP}:8008/app/configs - پیکربندی‌های برنامه"
echo -e "  http://${SERVER_IP}:8008/ads/configs - پیکربندی‌های تبلیغاتی"
echo -e "${YELLOW}امنیت:${NC}"
echo -e "  فایروال به صورت خودکار فعال شده و فقط پورت‌های ضروری باز هستند."
echo -e "  IP کاربران پس از استفاده موفق از سرویس به طور خودکار به لیست سفید اضافه می‌شوند."
echo -e "  برای مشاهده لیست IP های مجاز از دستور زیر استفاده کنید:"
echo -e "  ${BLUE}sudo /usr/local/bin/xui-firewall.sh --list${NC}"
echo -e "${GREEN}موفق باشید!${NC}"
