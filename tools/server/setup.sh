#!/data/data/com.termux/files/usr/bin/bash
# Installa il server di Flaminio nel telefono. Si lancia da Termux con:
#   termux-setup-storage        (una volta, per leggere la cartella Download)
#   bash ~/storage/downloads/flaminio/setup.sh
set -e
SRC="$HOME/storage/downloads/flaminio"
GODOT_URL="https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.arm64.zip"
echo "== 1/4 Pacchetti di Termux"
pkg update -y
pkg install -y proot-distro termux-tools
echo "== 2/4 Debian (circa 100 MB)"
proot-distro install debian || echo "(Debian c'era già)"
# Il file di avvio si copia "da dentro" Debian: la cartella di Debian cambia tra le versioni di proot-distro.
proot-distro login debian -- bash -c "cat > /root/avvia.sh && chmod +x /root/avvia.sh" < "$SRC/avvia.sh"
echo "== 3/4 Godot per ARM e strumenti (circa 70 MB)"
proot-distro login debian -- bash -c "
set -e
apt-get update
apt-get install -y git curl unzip ca-certificates libfontconfig1
mkdir -p /root/godot
if [ ! -x /root/godot/godot ]; then
	curl -L -o /root/godot/godot.zip '$GODOT_URL'
	unzip -o /root/godot/godot.zip -d /root/godot
	mv /root/godot/Godot_v4.7.2-stable_linux.arm64 /root/godot/godot
	chmod +x /root/godot/godot
	rm /root/godot/godot.zip
fi
/root/godot/godot --version
"
echo "== 4/4 Avvio automatico (Termux:Boot)"
mkdir -p "$HOME/.termux/boot"
cp "$SRC/termux-boot.sh" "$HOME/.termux/boot/flaminio"
chmod +x "$HOME/.termux/boot/flaminio"
echo
echo "Fatto. Avvio il server adesso (la prima volta scarica il gioco, circa 230 MB: qualche minuto)."
echo "Per vedere cosa fa:  proot-distro login debian -- tail -f /root/flaminio-server.log"
termux-wake-lock
nohup proot-distro login debian -- bash /root/avvia.sh >/dev/null 2>&1 &
echo "Server partito in sottofondo."
