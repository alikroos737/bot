#!/bin/bash

# Create the Python script
cat > check_servers.py << 'EOL'
import requests
import re
import subprocess
import platform
import json
import base64
from urllib.parse import urlparse, parse_qs
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

def ping(host, timeout=5):
    """
    Returns True if host responds to a ping request within timeout seconds
    """
    try:
        if not re.match(r'^(\d{1,3}\.){3}\d{1,3}$', host):
            return False
            
        param = '-n' if platform.system().lower() == 'windows' else '-c'
        command = ['ping', param, '1', host]
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            process.wait(timeout=timeout)
            return process.returncode == 0
        except subprocess.TimeoutExpired:
            process.kill()
            return False
    except:
        return False

def decode_base64(base64_str):
    """
    Decodes base64 string and returns JSON
    """
    try:
        # Add padding if needed
        padding = 4 - (len(base64_str) % 4)
        if padding != 4:
            base64_str += '=' * padding
        
        decoded = base64.b64decode(base64_str).decode('utf-8')
        return json.loads(decoded)
    except:
        return None

def extract_vless_info(vless_url):
    """
    Extracts address and port from VLESS URL
    """
    try:
        # Remove vless:// prefix
        url = vless_url.replace('vless://', '')
        # Split at @ to get the server part
        server_part = url.split('@')[1]
        # Split at ? to remove query parameters
        server_part = server_part.split('?')[0]
        # Split at : to separate IP and port
        address, port = server_part.split(':')
        return address, port
    except:
        return None, None

def extract_vmess_info(vmess_url):
    """
    Extracts address and port from VMess URL
    """
    try:
        # Remove vmess:// prefix
        base64_str = vmess_url.replace('vmess://', '')
        # Decode base64
        config = decode_base64(base64_str)
        if config:
            return config.get('add'), config.get('port')
    except:
        pass
    return None, None

def extract_base64_info(base64_str):
    """
    Extracts address and port from base64 encoded config
    """
    try:
        config = decode_base64(base64_str)
        if config and 'outbounds' in config:
            for outbound in config['outbounds']:
                if outbound.get('protocol') in ['vless', 'vmess']:
                    settings = outbound.get('settings', {})
                    vnext = settings.get('vnext', [{}])[0]
                    address = vnext.get('address')
                    port = vnext.get('port')
                    if address and port:
                        return address, port
    except:
        pass
    return None, None

def get_server_info(config):
    """
    Extracts server info based on config type
    """
    if config.startswith('vless://'):
        return extract_vless_info(config)
    elif config.startswith('vmess://'):
        return extract_vmess_info(config)
    else:
        return extract_base64_info(config)

def get_configs():
    """
    Fetches configs from the PHP API
    """
    try:
        response = requests.get('https://noor.elderemtm.com/app/Bot/get_configs.php')
        if response.status_code == 200:
            return response.json()
        return []
    except:
        return []

def check_server(config):
    address, port = get_server_info(config)
    if address and port:
        if ping(address):
            print(f"✅ {address}:{port} is working")
            return {
                'config': config,
                'status': 'working',
                'address': address,
                'port': port
            }
        else:
            print(f"❌ {address}:{port} is not responding")
            return {
                'config': config,
                'status': 'not_working',
                'address': address,
                'port': port
            }
    return None

def update_database(working_configs, not_working_configs):
    """
    Updates the database with working and not working configs
    """
    try:
        data = {
            'working': working_configs,
            'not_working': not_working_configs
        }
        response = requests.post('https://noor.elderemtm.com/app/Bot/update_configs.php', json=data)
        if response.status_code == 200:
            result = response.json()
            if result.get('success'):
                print("✅ Database updated successfully")
                return True
            else:
                print(f"❌ Update failed: {result.get('error', 'Unknown error')}")
        else:
            print(f"❌ Update failed with status code: {response.status_code}")
        return False
    except Exception as e:
        print(f"❌ Update error: {str(e)}")
        return False

def main():
    start_time = time.time()
    
    # Get configs from API
    configs = get_configs()
    print(f"Found {len(configs)} servers to check")
    
    # Store working and not working servers
    working_servers = []
    not_working_servers = []
    
    # Use ThreadPoolExecutor for parallel processing
    with ThreadPoolExecutor(max_workers=50) as executor:
        # Submit all tasks
        future_to_config = {executor.submit(check_server, config): config for config in configs}
        
        # Process results as they complete
        for future in as_completed(future_to_config):
            result = future.result()
            if result:
                if result['status'] == 'working':
                    working_servers.append(result['config'])
                else:
                    not_working_servers.append(result['config'])
    
    end_time = time.time()
    print(f"\nFound {len(working_servers)} working servers")
    print(f"Found {len(not_working_servers)} not working servers")
    print(f"Total time: {end_time - start_time:.2f} seconds")
    
    # Update database
    print("\nUpdating database...")
    update_database(working_servers, not_working_servers)

if __name__ == "__main__":
    main()
EOL

# Create the run script
cat > run_check.sh << 'EOL'
#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Create a log directory if it doesn't exist
mkdir -p "$SCRIPT_DIR/logs"

# Function to run the check
run_check() {
    echo "Running check at $(date)"
    python3 "$SCRIPT_DIR/check_servers.py" >> "$SCRIPT_DIR/logs/check_$(date +\%Y\%m\%d).log" 2>&1
}

# Run the check immediately
run_check

# Set up cron job to run every 7 minutes
(crontab -l 2>/dev/null; echo "*/7 * * * * $SCRIPT_DIR/run_check.sh") | crontab -

echo "Cron job has been set up to run every 7 minutes"
echo "Logs will be saved in $SCRIPT_DIR/logs directory"
EOL

# Make the run script executable
chmod +x run_check.sh

# Install required Python packages
pip3 install requests

# Run the script
./run_check.sh

echo "Setup completed successfully!" 
