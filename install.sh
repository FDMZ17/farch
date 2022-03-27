#!/bin/bash

printf '\033c'

echo -ne "
=========================================================================================
                                  ___                                                ___
 _____ _____ _____ _____ _____   |  _| _____ _____ _____ _____   _ _____ _____ _____ |_  |
|   __|  _  | __  |     |  |  |  | |  |  |  |   __|   __|     | / |   __|   __|     |  | |
|   __|     |    -|   --|     |  | |  |  |  |   __|   __|-   -|/ /|   __|   __|-   -|  | |
|__|  |__|__|__|__|_____|__|__|  | |_ |_____|_____|__|  |_____|_/ |_____|__|  |_____| _| |
                                 |___|                                               |___|

=========================================================================================
                          Automated archlinux installer
                                 [UEFI/EFI]

=========================================================================================
"

#installer1

sed -i "s/^#ParallelDownloads = 5$/ParallelDownloads = 10/" /etc/pacman.conf
pacman -Sy archlinux-keyring
echo 'Enter your keymaps: '
read keymaps
loadkeys $keymaps

# timedate
timedatectl set-ntp true

# getting the best mirrorlist
pacman --noconfirm -Syyy
pacman --noconfirm -S reflector
echo 'Country name for mirrors: '
read mirrorsRegion
reflector -c $mirrorsRegion -a 5 --sort rate --save /etc/pacman.d/mirrorlist

# disk partition
echo -ne "
========================================================================
    THIS WILL FORMAT AND DELETE ALL DATA ON THE DISK!
    Please make sure you know what you are doing because
    after formating your disk there is no way to get data back
========================================================================
"
echo "Avabile drive: $(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print "/dev/"$2" | "$3}')" 
echo 'Enter the drive: '
read driveToInstall
cfdisk $driveToInstall

echo "Please Select your file system for root: "
echo "ext4"
echo "btrfs"
echo "luks"
read partitionType

# efi
echo 'Enter EFI partition: '
read efiPartition
mkfs.vfat -F 32 $efiPartition

# root
echo "Enter the root partition: "
read rootPartition
mkfs.$partitionType $rootPartition -f
mount $rootPartition /mnt

# home
read -p "Did you also create home partition? [y/n]" answer
if [[ $answer = y ]] ; then
  echo "Enter home patition: "
  read homePartition
  mkfs.$partitionType $homePartition -f
  mkdir /mnt/home
  mount $homePartition /mnt/home
fi


# installing base system
pacstrap /mnt base-devel base linux linux-firmware vim git

# generate fstab
genfstab -U /mnt >> /mnt/etc/fstab
cat /mnt/etc/fstab

# arch-chroot
sed '1,/^#installer2$/d' `basename $0` > /mnt/farch-installer2.sh
chmod +x /mnt/farch-installer2.sh
arch-chroot /mnt ./farch-installer2.sh
exit 

#installer2
printf '\033c'
pacman -S --noconfirm sed
sed -i "s/^#ParallelDownloads = 5$/ParallelDownloads = 10/" /etc/pacman.conf

time_zone="$(curl --fail https://ipapi.co/timezone)"
echo "System detected your timezone to be '$time_zone' \n"
read -p "Is this correct? [y/n]" time_zone_answer
if [[ $time_zone_answer = y ]] ; then
	ln -sf /usr/share/zoneinfo/$time_zone /etc/localtime
else 
	echo 'Enter your timezone: '
	read fixTimezone
	ln -sf /usr/share/zoneinfo/$fixTimezone /etc/localtime
fi
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
echo "Hostname: "
read hostname
echo $hostname > /etc/hostname
echo "127.0.0.1       localhost" >> /etc/hosts
echo "::1             localhost" >> /etc/hosts
echo "127.0.1.1       $hostname.localdomain $hostname" >> /etc/hosts

mkinitcpio -P 

# installing more package
pacman -S grub efibootmgr os-prober

# root password
echo 'Enter your root password: '
passwd

# install grub
echo 'Enter efi partition: '
read efiPartitionForGrub
mkdir /boot/efi
mount $efiPartitionForGrub /boot/efi
echo 'grub target[i386-efi, x86_64-efi]: '
read grubTarget
grub-install --target=$grubTarget --efi-directory=/boot/efi --bootloader-id=arch-grub
grub-mkconfig -o /boot/grub/grub.cfg


pacman --noconfirm -S xdg-user-dirs networkmanager neofetch
systemctl enable NetworkManager.service

# add normal user
echo 'Enter the username for main user: '
read userNameForMainUser
useradd -mG wheel $userNameForMainUser
passwd $userNameForMainUser
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

echo "Installing packages"
pacman -S --noconfirm alsa-utils alsa-firmware sof-firmware alsa-ucm-conf dunst libnotify firefox ffmpeg mpv xorg-bdftopcf xorg-docs xorg-font-util xorg-fonts-100dpi xorg-fonts-75dpi xorg-fonts-encodings xorg-iceauth xorg-mkfontscale xorg-server xorg-server-common xorg-server-devel xorg-server-xephyr xorg-server-xnest xorg-server-xvfb xorg-sessreg xorg-setxkbmap xorg-smproxy xorg-x11perf xorg-xauth xorg-xbacklight xorg-xcmsdb xorg-xcursorgen xorg-xdpyinfo xorg-xdriinfo xorg-xev xorg-xgamma xorg-xhost xorg-xinit xorg-xinput xorg-xkbcomp xorg-xkbevd xorg-xkbutils xorg-xkill xorg-xlsatoms xorg-xlsclients xorg-xmodmap xorg-xpr xorg-xrandr xorg-xrdb xorg-xrefresh xorg-xsetroot xorg-xvinfo xorg-xwayland xorg-xwd xorg-xwininfo xorg-xwud 

gpu_type=$(lspci)
echo "Installing driver packages"
if grep -E "NVIDIA|GeForce" <<< ${gpu_type}; then
    pacman -S --noconfirm --needed nvidia
	nvidia-xconfig
elif lspci | grep 'VGA' | grep -E "Radeon|AMD"; then
    pacman -S --noconfirm --needed xf86-video-amdgpu
elif grep -E "Integrated Graphics Controller" <<< ${gpu_type}; then
    pacman -S --noconfirm --needed xf86-video-intel libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa
elif grep -E "Intel Corporation" <<< ${gpu_type}; then
    pacman -S --needed --noconfirm xf86-video-intel libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa
fi

echo 'Base system installation done!'
echo 'run umount -a && reboot'
exit

