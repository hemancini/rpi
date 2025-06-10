#!/bin/bash

# check if zsh is already installed
if command -v zsh >/dev/null 2>&1; then
  echo "Zsh is already installed."
  exit 0
fi

echo "Updating package lists and upgrading installed packages..."
apt update && apt upgrade -y

echo "Installing Zsh and Oh My Zsh..."
apt install -y git zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

apt install -y zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
echo "source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >>~/.zshrc

apt install -y zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
echo "source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" >>~/.zshrc

# change zsh theme to fwalch
sed -i 's/ZSH_THEME=.*/ZSH_THEME="fwalch"/g' ~/.zshrc

echo "Adding zsh-sytem-information plugin..."
git clone https://github.com/hemancini/zsh-sytem-information.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-sytem-information
sed -i 's/plugins=(/plugins=(zsh-sytem-information /g' ~/.zshrc

echo "=================================================="
echo "Oh My Zsh and plugins installed successfully!"
echo "=================================================="
