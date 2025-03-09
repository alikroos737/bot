#!/bin/bash

# رنگ‌ها برای بهبود خوانایی خروجی
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # بدون رنگ

echo -e "${BLUE}=== شروع نصب اتوماتیک XUI Manager ===${NC}"

# بررسی سیستم‌عامل
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${YELLOW}سیستم‌عامل قابل شناسایی نیست. فرض می‌شود Debian/Ubuntu است.${NC}"
    OS="debian"
fi

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

# ذخیره اسکریپت اصلی
echo -e "${YELLOW}در حال آماده‌سازی فایل اصلی...${NC}"
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
from flask import Flask, jsonify, request

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

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
            print(f"Attempting to login to {url}")
            
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
            
            print(f"Login response status: {response.status_code}")
            
            # Extract cookies from response
            cookies = response.cookies
            for cookie in cookies:
                print(f"Found cookie: {cookie.name} = {cookie.value}")
                if cookie.name in ['3x-ui', 'session', 'token']:
                    return cookie.value
            
            # Try to extract from cookie header if not found in cookies object
            cookie_header = response.headers.get('Set-Cookie')
            if cookie_header:
                print(f"Cookie header found: {cookie_header[:100]}...")
                
                # Try to extract various possible cookie names
                for cookie_name in ['3x-ui', 'session', 'token']:
                    match = re.search(f'{cookie_name}=([^;]*)', cookie_header)
                    if match:
                        cookie_value = match.group(1)
                        print(f"Extracted {cookie_name} cookie: {cookie_value[:10]}...")
                        return cookie_value
            
            print("No authentication cookie found in response")
            return None
        except Exception as e:
            print(f"Login error: {str(e)}")
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
                print(f"Trying to fetch inbounds from {url}")
                
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
                        print(f"Successful response from {endpoint} with headers {headers}")
                        print(f"Response preview: {response.text[:100]}...")
                        
                        # Check if the response looks like valid JSON with inbounds data
                        try:
                            data = response.json()
                            # Look for common keys that would indicate inbound data
                            if 'obj' in data or 'inbounds' in data or 'data' in data:
                                return self.generate_custom_format(response.text, data, config_type)
                        except json.JSONDecodeError:
                            print(f"Response is not valid JSON from {endpoint}")
                            continue
            except Exception as e:
                print(f"Error fetching from {endpoint}: {str(e)}")
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
                print("No inbounds found in response")
                return json.dumps({
                    'status': 'error', 
                    'message': 'No inbounds found in response'
                })
                
            print(f"Found {len(inbounds)} inbounds")
            
            for inbound in inbounds:
                inbound_id = inbound.get('id', 'unknown')
                print(f"Processing inbound: {inbound_id}")
                
                # Parse the settings and stream settings - handle both string and object formats
                settings = inbound.get('settings', {})
                if isinstance(settings, str):
                    try:
                        settings = json.loads(settings)
                    except json.JSONDecodeError:
                        print(f"Error parsing settings for inbound {inbound_id}")
                        continue
                        
                stream_settings = inbound.get('streamSettings', {})
                if isinstance(stream_settings, str):
                    try:
                        stream_settings = json.loads(stream_settings)
                    except json.JSONDecodeError:
                        print(f"Error parsing streamSettings for inbound {inbound_id}")
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
                    print(f"No clients found for inbound {inbound_id}")
                    continue
                
                print(f"Found {len(clients)} clients for inbound {inbound_id}")
                    
                for client in clients:
                    config = self.build_custom_config(client, inbound, stream_settings, config_type)
                    if config:
                        configs.append(config)
                        
            # Create the custom format response
            result = {
                "status": "success",
                "data": {
                    "configs": configs
                }
            }
            
            return json.dumps(result)
        except Exception as e:
            print(f"Error generating configs: {str(e)}")
            import traceback
            traceback.print_exc()
            return json.dumps({'status': 'error', 'message': f'Error generating configs: {str(e)}'})
            
    def build_custom_config(self, client, inbound, stream_settings, config_type="app"):
        """Build custom format config for a client"""
        try:
            client_id = client.get('id', client.get('password', ''))
            client_email = client.get('email', 'unknown')
            
            print(f"Building config for client: {client_email}")
            
            if not client_id:
                print(f"No valid ID found for client {client_email}")
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
            print(f"Error building custom config: {str(e)}")
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
            print(f"Error building VLESS config: {str(e)}")
            return None
            
    def handle_security_settings(self, stream_settings, params):
        """Process security settings"""
        security = stream_settings.get('security', 'none')
        print(f"Security type: {security}")
        
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
        print(f"Local IP detected via socket: {local_ip}")
        return local_ip
    except Exception as e:
        print(f"Socket method failed: {str(e)}")
        try:
            # Second attempt: try to get IP from hostname
            result = subprocess.run(['hostname', '-I'], stdout=subprocess.PIPE)
            ip = result.stdout.decode('utf-8').strip().split()[0]
            if ip:
                print(f"Local IP detected via hostname: {ip}")
                return ip
        except Exception as e:
            print(f"Hostname method failed: {str(e)}")
        
        # Fallback to localhost if all methods fail
        print("Falling back to localhost (127.0.0.1)")
        return "127.0.0.1"

# Flask server
app = Flask(__name__)

@app.route('/')
def home():
    return """
    <html>
    <head><title>XUI Manager</title></head>
    <body>
        <h1>XUI Manager server is running</h1>
        <p>Use <a href="/app/configs">/app/configs</a> for app configurations.</p>
        <p>Use <a href="/ads/configs">/ads/configs</a> for ads configurations.</p>
    </body>
    </html>
    """

@app.route('/app/configs')
def get_app_configs():
    """Get configurations for app usage"""
    try:
        local_ip = get_local_ip()
        print(f"Using local IP: {local_ip}")
        
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
        return jsonify(response_json)
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'status': 'error', 'message': f'Server error: {str(e)}'})

@app.route('/ads/configs')
def get_ads_configs():
    """Get configurations for ads usage"""
    try:
        local_ip = get_local_ip()
        print(f"Using local IP: {local_ip}")
        
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
        return jsonify(response_json)
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'status': 'error', 'message': f'Server error: {str(e)}'})

# Backwards compatibility
@app.route('/configs')
def get_configs():
    """Default configs endpoint (uses app type)"""
    return get_app_configs()

if __name__ == '__main__':
    print("Starting XUI Manager server on port 8008...")
    app.run(host='0.0.0.0', port=8008, debug=False)
EOF

# تغییر مجوز اجرایی فایل
chmod +x xui_manager.py

# ایجاد فایل سرویس systemd برای اجرای خودکار در هنگام بوت
echo -e "${YELLOW}در حال ایجاد سرویس سیستمی برای اجرای خودکار...${NC}"

SERVICE_PATH="/etc/systemd/system/xui-manager.service"

cat > $SERVICE_PATH << EOF
[Unit]
Description=XUI Manager Service
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

# بررسی وضعیت سرویس
echo -e "${YELLOW}در حال بررسی وضعیت سرویس...${NC}"
sleep 2
systemctl status xui-manager.service

# نمایش اطلاعات نهایی
SERVER_IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
echo -e "${GREEN}=== نصب XUI Manager به پایان رسید ===${NC}"
echo -e "${GREEN}سرویس با موفقیت راه‌اندازی شد و به صورت خودکار در هنگام بوت اجرا خواهد شد.${NC}"
echo -e "${BLUE}آدرس دسترسی:${NC}"
echo -e "  http://${SERVER_IP}:8008 - صفحه اصلی"
echo -e "  http://${SERVER_IP}:8008/app/configs - پیکربندی‌های برنامه"
echo -e "  http://${SERVER_IP}:8008/ads/configs - پیکربندی‌های تبلیغاتی"
