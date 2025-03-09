#!/bin/bash

# XUI Manager Automated Setup Script
# This script installs all required dependencies and sets up the service

# Text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}       3x-ui XUI Manager Automatic Setup           ${NC}"
echo -e "${BLUE}====================================================${NC}"

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run this script as root or with sudo${NC}"
  exit 1
fi

# Create install directory
INSTALL_DIR="/opt/xui-manager"
echo -e "${YELLOW}Creating installation directory at ${INSTALL_DIR}...${NC}"
mkdir -p $INSTALL_DIR

# Check Python version
echo -e "${YELLOW}Checking Python version...${NC}"
    if command -v python3 &>/dev/null; then
  PYTHON_CMD="python3"
else
  if command -v python &>/dev/null; then
    PYTHON_CMD="python"
  else
    echo -e "${RED}Python is not installed. Installing Python 3...${NC}"
    apt update
    apt install -y python3 python3-pip
    PYTHON_CMD="python3"
  fi
fi

# Install pip if not available
if ! $PYTHON_CMD -m pip --version &>/dev/null; then
  echo -e "${YELLOW}pip not found. Installing pip...${NC}"
  apt update
  apt install -y python3-pip
fi

echo -e "${GREEN}Using Python command: $PYTHON_CMD${NC}"

# Install required packages
echo -e "${YELLOW}Installing required packages...${NC}"
$PYTHON_CMD -m pip install flask requests

# Create the Python script
echo -e "${YELLOW}Creating XUI Manager Python script...${NC}"
cat > $INSTALL_DIR/xui_manager.py << 'EOL'
import requests
import json
import urllib.parse
import re
import socket
from flask import Flask, jsonify

class XuiManager:
    def __init__(self):
        # Fixed credentials as per your requirements
        self.username = "zahed"
        self.password = "zahed2341"
        self.port = 80
        self.ssl = False
        self.server_ip = "127.0.0.1"  # Always use localhost
        self.cookie = self.login_and_get_cookie()
        
    def login_and_get_cookie(self):
        """Login to 3x-ui panel and get authentication cookie"""
        protocol = "https" if self.ssl else "http"
        url = f"{protocol}://{self.server_ip}:{self.port}/login"
        
        try:
            response = requests.post(
                url,
                data=f"username={self.username}&password={self.password}",
                timeout=(10, 30)
            )
            
            # Extract cookie from response
            cookies = response.cookies
            if '3x-ui' in cookies:
                return cookies['3x-ui']
            
            # Try to extract from headers if not in cookies object
            cookie_header = response.headers.get('Set-Cookie')
            if cookie_header:
                match = re.search(r'3x-ui=([^;]*)', cookie_header)
                if match:
                    return match.group(1)
                    
            return None
        except Exception as e:
            print(f"Login error: {str(e)}")
            return None
            
    def fetch_inbounds_list(self):
        """Fetch inbounds list from 3x-ui panel"""
        protocol = "https" if self.ssl else "http"
        url = f"{protocol}://{self.server_ip}:{self.port}/panel/api/inbounds/list"
        
        try:
            headers = {
                'Accept': 'application/json',
                'Cookie': f'3x-ui={self.cookie}'
            }
            
            response = requests.get(
                url,
                headers=headers,
                timeout=(10, 30),
                verify=False if self.ssl else True
            )
            
            if response.status_code == 200:
                return self.generate_vless_configs(response.text)
            
            return json.dumps({'success': False, 'message': 'Invalid response'})
        except Exception as e:
            return json.dumps({'success': False, 'message': f'Error: {str(e)}'})
            
    def generate_vless_configs(self, json_response):
        """Generate VLESS configs from inbounds response"""
        try:
            response = json.loads(json_response)
            configs = []
            
            for inbound in response.get('obj', []):
                settings = json.loads(inbound.get('settings', '{}'))
                stream_settings = json.loads(inbound.get('streamSettings', '{}'))
                
                if not settings.get('clients'):
                    continue
                    
                for client in settings['clients']:
                    config = self.build_vless_config(client, inbound, stream_settings)
                    if config:
                        configs.append(config)
                        
            return json.dumps({
                'success': True,
                'configs': configs
            })
        except Exception as e:
            return json.dumps({'success': False, 'message': f'Error generating configs: {str(e)}'})
            
    def build_vless_config(self, client, inbound, stream_settings):
        """Build VLESS config for a client"""
        try:
            config = f"vless://{client['id']}@{self.server_ip}:{inbound['port']}?"
            params = {'type': stream_settings.get('network', 'tcp')}
            
            self.handle_security_settings(stream_settings, params)
            
            query_string = urllib.parse.urlencode(params)
            remark = self.generate_remark(inbound.get('remark', ''), client.get('email', ''))
            
            return f"{config}{query_string}#{urllib.parse.quote(remark)}"
        except Exception as e:
            print(f"Error building config: {str(e)}")
            return None
            
    def handle_security_settings(self, stream_settings, params):
        """Process security settings"""
        security = stream_settings.get('security', 'none')
        
        if security == 'none':
            self.handle_none_security(stream_settings, params)
        elif security == 'reality':
            self.handle_reality_security(stream_settings, params)
            
    def handle_none_security(self, stream_settings, params):
        """Process 'none' security settings"""
        if (stream_settings.get('network') == 'tcp' and
            stream_settings.get('tcpSettings', {}).get('header', {}).get('type') == 'http'):
            
            tcp_settings = stream_settings.get('tcpSettings', {})
            headers = tcp_settings.get('header', {}).get('request', {}).get('headers', {})
            
            params['path'] = '/'
            if 'Host' in headers and headers['Host']:
                params['host'] = headers['Host'][0]
            params['headerType'] = 'http'
            params['security'] = 'none'
            
    def handle_reality_security(self, stream_settings, params):
        """Process 'reality' security settings"""
        reality_settings = stream_settings.get('realitySettings', {})
        settings = reality_settings.get('settings', {})
        
        params['security'] = 'reality'
        params['pbk'] = settings.get('publicKey', '')
        params['fp'] = settings.get('fingerprint', '')
        
        server_names = reality_settings.get('serverNames', [])
        if server_names:
            params['sni'] = server_names[0]
            
        short_ids = reality_settings.get('shortIds', [])
        if short_ids:
            params['sid'] = short_ids[0]
            
        params['spx'] = settings.get('spiderX', '')
        
    def generate_remark(self, remark, email):
        """Generate remark for config"""
        return f"{remark}-{email}"

# Function to get local IP
def get_local_ip():
    try:
        # First attempt: try to get IP via socket connection
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))  # Connect to Google DNS
        local_ip = s.getsockname()[0]
        s.close()
        return local_ip
    except:
        try:
            # Second attempt: try to get IP from hostname
            import subprocess
            result = subprocess.run(['hostname', '-I'], stdout=subprocess.PIPE)
            ip = result.stdout.decode('utf-8').strip().split()[0]
            if ip:
                return ip
        except:
            pass
        
        # Fallback to localhost if all methods fail
        return "127.0.0.1"

# Flask server
app = Flask(__name__)

@app.route('/')
def home():
    return "XUI Manager server is running. Use /configs to get configurations."

@app.route('/configs')
def get_configs():
    try:
        xui_manager = XuiManager()
        # Set the server IP to local IP for the config URLs
        xui_manager.server_ip = get_local_ip()
        response_text = xui_manager.fetch_inbounds_list()
        response_json = json.loads(response_text)
        return jsonify(response_json)
    except Exception as e:
        return jsonify({'success': False, 'message': f'Server error: {str(e)}'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8008, debug=False)
EOL

echo -e "${GREEN}XUI Manager Python script created successfully!${NC}"

# Create systemd service file
echo -e "${YELLOW}Creating systemd service file...${NC}"
cat > /etc/systemd/system/xui-manager.service << EOL
[Unit]
Description=XUI Manager Python Server
After=network.target

[Service]
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${PYTHON_CMD} ${INSTALL_DIR}/xui_manager.py
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Make the Python script executable
chmod +x $INSTALL_DIR/xui_manager.py

# Create the README file
echo -e "${YELLOW}Creating README file...${NC}"
cat > $INSTALL_DIR/README.md << 'EOL'
# XUI Manager Python

This service automatically fetches and converts configurations from a local 3x-ui panel.

## Usage

Once installed, you can access the configurations at:

```
http://your_server_ip:8008/configs
```

## Service Management

### Check status
```
systemctl status xui-manager
```

### Restart service
```
systemctl restart xui-manager
```

### View logs
```
journalctl -u xui-manager -f
```

## Configuration

The service is configured to connect to a local 3x-ui panel with:
- Username: zahed
- Password: zahed2341
- Port: 80

To modify these settings, edit the Python script at:
```
/opt/xui-manager/xui_manager.py
```
EOL

# Enable and start the service
echo -e "${YELLOW}Enabling and starting the service...${NC}"
systemctl daemon-reload
systemctl enable xui-manager.service
systemctl start xui-manager.service

# Check if the service is running
if systemctl is-active --quiet xui-manager.service; then
  echo -e "${GREEN}XUI Manager service is now running!${NC}"
else
  echo -e "${RED}Failed to start XUI Manager service. Please check logs with: journalctl -u xui-manager -e${NC}"
  exit 1
fi

# Get the server IP
# Define the get_local_ip function in this scope too so it can be called directly
get_local_ip() {
    hostname -I | awk '{print $1}'
}
SERVER_IP=$(get_local_ip)

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}XUI Manager has been successfully installed!${NC}"
echo -e "${GREEN}You can access it at: http://${SERVER_IP}:8008/configs${NC}"
echo -e "${YELLOW}Service installed at: ${INSTALL_DIR}${NC}"
echo -e "${YELLOW}Service logs can be viewed with: journalctl -u xui-manager -f${NC}"
echo -e "${BLUE}====================================================${NC}"

exit 0
