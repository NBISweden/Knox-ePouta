# -*-sh-*-

source ${SCRIPT_FOLDER:-.}/common.sh

echo "Installing Thinlinc packages"
yum -y install *x86_64.rpm *noarch.rpm xauth

echo "Setting up Thinlinc"
/opt/thinlinc/sbin/tl-setup -a tl_answers

echo "Configuring Thinlinc web access"
sed -i 's/^listen=.*$/listen=443/' /opt/thinlinc/etc/conf.d/webaccess.hconf

