#!/bin/bash

set -e

FAKEUSER_PROMPT_PREFIX=$'\033[1m(\033[31mfakeuser\033[0m\033[1m '
FAKEUSER_PROMPT_SUFFIX=$') \033[0m'

# check the folder of fakeuser in argument
if [ $# = 0 ]; then
  fu_dir=$PWD
elif [ $# = 1 ]; then
  fu_dir=$(realpath $1)
else
  echo "Usage: $0 [<path/to/fakeuser>]"
  exit 1
fi

echo -n "Checking for openssl..."
if ! command -v openssl &> /dev/null; then
  echo "Error: openssl is required but not installed. Please install it and try again."
  exit 1
fi
echo "ok"

echo -n "Checking for ssh-keygen..."
if ! command -v ssh-keygen &> /dev/null; then
  echo "Error: ssh-keygen is required but not installed. Please install it and try again."
  exit 1
fi
echo "ok"

echo -n "Checking for realpath..."
if ! command -v realpath &> /dev/null; then
  echo "Error: realpath is required but not installed. Please install it and try again."
  exit 1
fi
echo "ok"

fu_config="$fu_dir/.fakeuser"
fu_login="$fu_dir/login"
fu_shadow="$fu_config/shadow"
fu_bin="$fu_config/bin"
fu_sbin="$fu_config/sbin"
fu_askpass="$fu_bin/ssh_passphrase"
fu_manage="$fu_sbin/fakeuser"

mkdir -p "$fu_config"
mkdir -p "$fu_bin"
mkdir -p "$fu_sbin"
touch "$fu_shadow"
touch "$fu_askpass"
touch "$fu_manage"
touch "$fu_login"
# Create askpass script
cat <<EOF > "$fu_askpass"
#!/bin/bash
echo \$FAKEUSER_SSH_PASSPHRASE
EOF
chmod +x "$fu_askpass"

# Create login script
cat <<EOF > "$fu_login"
#!/bin/bash
if [[ \$HOME == $fu_dir/* ]]; then
    echo 'Already enabled. use \`exit\` to exit environment.'
    exit 1
fi

while true; do
  read -p "Enter login name: " fakeuser_login
  if [ -z "\$fakeuser_login" ]; then
    echo "Error: login name cannot be empty. Please try again."
    continue
  fi
  MAX_TRY=3
  CORRECT=0
  for i in \$(seq 1 \$MAX_TRY); do
    target_line=\$(cat $fu_shadow | grep -e "^\$fakeuser_login:")
    if [ \$? -ne 0 ]; then
      echo -n "Enter password: "
      read -s fakeuser_passwd
      echo
      echo "Wrong credentials" > /dev/stderr
      continue
    fi
    target_hash=\$(echo \$target_line | cut -d: -f2)
    fakeuser_home=\$(echo \$target_line | cut -d: -f3)
    fakeuser_shell=\$(echo \$target_line | cut -d: -f4)
    if [ -z \$target_hash ]; then
      # set password
      while true; do
        read -s -p "Enter new password: " fakeuser_passwd
        echo
        read -s -p "Confirm password: " fakeuser_passwd_confirm
        echo
        if [ "\$fakeuser_passwd" = "\$fakeuser_passwd_confirm" ]; then
          break
        fi
        echo "Error: password and confirm password not match. Please try again." > /dev/stderr
      done
      SALT=\$(openssl rand -base64 16)
      HASH=\$(openssl passwd -6 -salt \$SALT \$fakeuser_passwd)
      
      rm -f "\$fakeuser_home/.ssh/id_ed25519"
      rm -f "\$fakeuser_home/.ssh/id_ed25519.pub"
      ssh-keygen -t ed25519 -N "\$fakeuser_passwd" -f "\$fakeuser_home/.ssh/id_ed25519" -C "\$(whoami).\$fakeuser_login@\$HOSTNAME" | tail -n 12
      
      os=\$(uname -s)
      if [ \$os = Linux ]; then
        sed -i -e "/^\$fakeuser_login:.*/d" "$fu_shadow"
      elif [ \$os = Darwin ]; then
        sed -i '' -e "/^\$fakeuser_login:.*/d" "$fu_shadow"
      fi
      echo "\$fakeuser_login:\$HASH:\$fakeuser_home:\$fakeuser_shell" >> "$fu_shadow"
      echo "Password set for \$fakeuser_login"
      CORRECT=1
      break
    fi

    echo -n "Enter password: "
    read -s fakeuser_passwd
    echo
    crypt_method=\$(echo \$target_hash | cut -d$ -f2)
    salt=\$(echo \$target_hash | cut -d$ -f3)
    if [[ \$crypt_method == "6" ]]; then
      salted_hash=\$(echo -n \$fakeuser_passwd | openssl passwd -6 -salt \$salt \$fakeuser_passwd)
    elif [[ \$crypt_method == "1" ]]; then
      salted_hash=\$(echo -n \$fakeuser_passwd | openssl passwd -1 -salt \$salt \$fakeuser_passwd)
    else
      echo "Unsupported crypto method \$crypt_method" > /dev/stderr
      echo "The fakeuser shadow is corrupted. Please contact admin." > /dev/stderr
      exit 1
    fi
    if [[ \$salted_hash = \$target_hash ]]; then
      CORRECT=1
      break
    else
      echo "Wrong credentials" > /dev/stderr
    fi
  done
  if [[ \$CORRECT == 1 ]]; then
    break
  else
    exit 1
  fi
done

FAKEUSER_SSH_PASSPHRASE=\$fakeuser_passwd SSH_ASKPASS=$fu_askpass SSH_ASKPASS_REQUIRE=force HOME=\$fakeuser_home ZDOTDIR=\$fakeuser_home USER=\$fakeuser_login SHELL=\$fakeuser_shell PS1="${FAKEUSER_PROMPT_PREFIX}\$fakeuser_login${FAKEUSER_PROMPT_SUFFIX}\$PS1" PROMPT="${FAKEUSER_PROMPT_PREFIX}\$fakeuser_login${FAKEUSER_PROMPT_SUFFIX}\$PROMPT" \$fakeuser_shell

EOF
chmod +x "$fu_login"

# Create manage script
cat <<EOF > "$fu_manage"
#!/bin/bash

if [ \$# -lt 1 ]; then
  echo "Usage: \$0 add|del"
  exit 1
fi

case \$1 in
  add)
    if [ \$# -ne 2 ]; then
        echo "Usage: \$0 add <username>"
        exit 1
    fi
    fakeuser_login=\$2

    target_line=\$(cat $fu_shadow | grep -e "^\$fakeuser_login:")
    if [ \$? = 0 ]; then
      echo "User \$fakeuser_login already exists" > /dev/stderr
      continue
    fi
    fakeuser_home="$fudir/\$fakeuser_login"
    fakeuser_shell="\$SHELL" # using admin's current shell
    
    mkdir -p "\$fakeuser_home/.ssh"
    echo "\$fakeuser_login::\$fakeuser_home:\$fakeuser_shell" >> "$fu_shadow"

    # Create shell profile
    os=\$(uname -s)
    if [[ \$fakeuser_shell == *bash ]]; then
      shell_profile="\$fakeuser_home/.bashrc"
      if [ \$os = Linux ]; then
        default_shell_profile="/etc/skel/.bashrc"
      elif [ \$os = Darwin ]; then
        default_shell_profile="/etc/bashrc"
      fi
    elif [[ \$fakeuser_shell == *zsh ]]; then
      shell_profile="\$fakeuser_home/.zshrc"
      if [ \$os = Linux ]; then
        default_shell_profile="/etc/skel/.zshrc"
      elif [ \$os = Darwin ]; then
        default_shell_profile="/etc/zshrc"
      fi
    else
      echo "Warning: unknown shell \$fakeuser_shell. skip copy default shell profile." >> /dev/stderr
    fi

    if [ ! -f "\$shell_profile" ]; then
      if [ -f "\$default_shell_profile" ]; then
        cp "\$default_shell_profile" "\$shell_profile"
        chmod 644 "\$shell_profile"
        echo "export PATH=\"$fu_bin:\\\$PATH\"" >> "\$shell_profile"
        echo "export GIT_SSH_COMMAND=\"$(which ssh) -i \$fakeuser_home/.ssh/id_ed25519\"" >> "\$shell_profile"
        sed_command="s/PS1=\"\(.*\)\"/PS1=\"${FAKEUSER_PROMPT_PREFIX}\${fakeuser_login}${FAKEUSER_PROMPT_SUFFIX}\1\"/" # using suffix from fakeuser.sh
        if [ \$os = Linux ]; then
          sed -i -e "\$sed_command" "\$shell_profile"
        elif [ \$os = Darwin ]; then
          sed -i '' -e "\$sed_command" "\$shell_profile"
        fi
      else
        echo "Warning: default shell profile \$default_shell_profile not found. skip copy."
      fi
    fi
    echo "User \$fakeuser_login added, password will be added at first login"
    ;;
  del)
    if [ \$# -ne 2 ]; then
        echo "Usage: \$0 del <username>"
        exit 1
    fi
    fakeuser_login=\$2
    target_line=\$(cat $fu_shadow | grep -e "^\$fakeuser_login:")
    if [ \$? -ne 0 ]; then
      echo "User not found" > /dev/stderr
      continue
    fi
    if [ \$fakeuser_login = "admin" ]; then
      echo "Error: cannot delete admin user." > /dev/stderr
      exit 1
    fi
    os=\$(uname -s)
    if [ \$os = Linux ]; then
      sed -i -e "/^\$fakeuser_login:.*/d" "$fu_shadow"
    elif [ \$os = Darwin ]; then
      sed -i '' -e "/^\$fakeuser_login:.*/d" "$fu_shadow"
    fi
    echo "User \$fakeuser_login deleted"
    ;;
  *)
    echo "Usage: \$0 add|del"
    exit 1
    ;;
esac
EOF
chmod +x "$fu_manage"

# ========= create admin =========

admin_home="$fu_dir/admin"
fu_shadow_content=$(cat "$fu_shadow")
if [[ ! -z $fu_shadow_content ]]; then
  read -p "Fakeuser already exists in \"$fu_shadow\". recreate it? y/n: " ans
  if [ "$ans" != "y" ]; then
    exit 1
  fi
fi

rm -f "$fu_shadow"

admin_shell=$SHELL

mkdir -p "$admin_home/.ssh"

# Read password for admin
while true; do
  read -s -p "Enter password for admin: " admin_password
  echo
  if [ "$admin_password" = "" ]; then
    echo "Error: password cannot be empty. Please try again."
    continue
  fi
  read -s -p "Confirm password for admin: " admin_password_confirm
  echo
  if [ "$admin_password" = "$admin_password_confirm" ]; then
    break
  fi
  echo "Error: password and confirm password not match. Please try again." > /dev/stderr
done
SALT=$(openssl rand -base64 16)
ADMIN_HASH=$(openssl passwd -6 -salt $SALT $admin_password)
echo "admin:$ADMIN_HASH:$admin_home:$admin_shell" >> "$fu_shadow"

rm -f "$admin_home/.ssh/id_ed25519"
rm -f "$admin_home/.ssh/id_ed25519.pub"
# Create ssh key for admin
ssh-keygen -t ed25519 -N $admin_password -f "$admin_home/.ssh/id_ed25519" -C "$(whoami).admin@$HOSTNAME" | tail -n 12

# Create shell profile
os=$(uname -s)

if [[ $admin_shell == *bash ]]; then
  shell_profile="$admin_home/.bashrc"
  if [ $os = Linux ]; then
    default_shell_profile="/etc/skel/.bashrc"
  elif [ $os = Darwin ]; then
    default_shell_profile="/etc/bashrc"
  fi
elif [[ $admin_shell == *zsh ]]; then
  shell_profile="$admin_home/.zshrc"
  if [ $os = Linux ]; then
    default_shell_profile="/etc/skel/.zshrc"
  elif [ $os = Darwin ]; then
    default_shell_profile="/etc/zshrc"
  fi
else
  echo "Warning: unknown shell $admin_shell. skip copy default shell profile." >> /dev/stderr
fi
if [ ! -f "$shell_profile" ]; then
  if [ -f "$default_shell_profile" ]; then
    cp "$default_shell_profile" "$shell_profile"
    chmod 644 "$shell_profile"
    echo "export PATH=\"$fu_sbin:$fu_bin:\$PATH\"" >> "$shell_profile"
    echo "export GIT_SSH_COMMAND=\"$(which ssh) -i $admin_home/.ssh/id_ed25519\"" >> "$shell_profile"
    sed_command="s/PS1=\"\(.*\)\"/PS1=\"${FAKEUSER_PROMPT_PREFIX}admin${FAKEUSER_PROMPT_SUFFIX}\1\"/"
    if [ $os = Linux ]; then
      sed -i -e "$sed_command" "$shell_profile"
    elif [ $os = Darwin ]; then
      sed -i '' -e "$sed_command" "$shell_profile"
    fi
  else
    echo "Warning: default shell profile $default_shell_profile not found. skip copy."
  fi
fi
