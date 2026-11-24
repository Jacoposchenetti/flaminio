#!/data/data/com.termux/files/usr/bin/sh
# Va in ~/.termux/boot/ di Termux: all'accensione tiene sveglio il telefono e avvia il server dentro Debian.
termux-wake-lock
proot-distro login debian -- bash /root/avvia.sh
