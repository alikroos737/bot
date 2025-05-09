#!/bin/bash

# تشخیص مسیر فعلی
CURRENT_DIR=$(pwd)
SCRIPT_PATH="$CURRENT_DIR/check_timeout.sh"
LOG_PATH="$CURRENT_DIR/timeout_log.txt"

echo "در حال نصب اسکریپت در مسیر: $SCRIPT_PATH"

# ۱. ذخیره فایل اسکریپت
cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash

check_timeout() {
    local IP=$(hostname -I | cut -d' ' -f1)
    local RESPONSE=$(curl -s "https://check-host.net/check-ping" -H "Accept: application/json" -d "host=8.8.8.8")
    local REQUEST_ID=$(echo $RESPONSE | grep -oP '(?<="request_id":")[^"]*')
    
    if [ -z "$REQUEST_ID" ]; then
        echo "خطا: شناسه درخواست دریافت نشد" >> $(dirname "$0")/timeout_log.txt
        return 1
    fi
    
    sleep 30
    
    local RESULT=$(curl -s "https://check-host.net/check-result/$REQUEST_ID" -H "Accept: application/json")
    local TIMEOUT_COUNT=$(echo $RESULT | grep -o '"TIMEOUT"' | wc -l)
    
    # ارسال نتیجه به سرور مشخص شده
    curl -X POST "https://elderemtm.com/cheker/index.php" \
      -H "Content-Type: application/json" \
      -d "{\"ip\":\"$IP\", \"timeout_count\":\"$TIMEOUT_COUNT\", \"result\":$RESULT}"
    
    echo "تعداد تایم‌اوت: $TIMEOUT_COUNT - تاریخ: $(date)" >> $(dirname "$0")/timeout_log.txt
    return 0
}

# اجرای تابع
check_timeout
EOF

# ۲. اعطای مجوز اجرا به اسکریپت
chmod +x "$SCRIPT_PATH"

# اجرای اولیه اسکریپت برای تست
echo "در حال تست اسکریپت..."
"$SCRIPT_PATH"

# ۳. افزودن وظیفه به crontab برای اجرا هر ۱۰ دقیقه
(crontab -l 2>/dev/null || echo "") | grep -v "check_timeout.sh" | { cat; echo "*/5 * * * * $SCRIPT_PATH"; } | crontab -

echo "اسکریپت با موفقیت نصب شد و هر ۱۰ دقیقه اجرا خواهد شد."
echo "نتایج در فایل $LOG_PATH ذخیره می‌شوند."
echo "می‌توانید با دستور زیر وضعیت کرانتب را بررسی کنید:"
echo "crontab -l"
