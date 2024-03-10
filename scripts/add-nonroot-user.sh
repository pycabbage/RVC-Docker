#!/bin/bash -e

NEW_USER=$1

echo "Adding new user: \"$NEW_USER\""

if [ -z "$NEW_USER" ]; then
  echo "Usage: $0 <new-user>"
  exit 1
fi

# Create a new user
adduser --disabled-password --gecos "" $NEW_USER

# check if "sudo" and "visudo" is in PATH
# if command -v sudo &> /dev/null; then
  # Add the new user to the sudo group
usermod -aG sudo $NEW_USER

# Add the new user to sudoers
mkdir -p /etc/sudoers.d
echo "$NEW_USER ALL=NOPASSWD: ALL" > /etc/sudoers.d/$NEW_USER
chmod 0440 /etc/sudoers.d/$NEW_USER
if command -v visudo &> /dev/null; then
  visudo -c
fi

# else
#   echo "sudo is not installed. Please install sudo and add the new user to the sudo group manually."
# fi

