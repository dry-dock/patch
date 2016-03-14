echo 'Removing google chrome from updation list'
rm -f /etc/apt/sources.list.d/google-chrome.list
cd /var/lib/apt
sudo mv lists lists.old
sudo mkdir -p lists/partial
sudo apt-get update
