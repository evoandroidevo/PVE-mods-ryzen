#!/bin/bash
#This bash script installs a modification to the Proxmox Virtual Environment (PVE) web user interface (UI) to display temperature information.

# Filepaths
pvemanagerlib="/usr/share/pve-manager/js/pvemanagerlib.js"
nodespm="/usr/share/perl5/PVE/API2/Nodes.pm"
backuplocation="/root/backup"
timestamp=$(date '+%Y-%m-%d_%H-%M-%S')


################### code below #############
echo ""

# Function to display usage information
function usage {
  echo "Usage: $0 [install | uninstall]"
  echo ""
  exit 1
}

#!/bin/bash

# Define a function to install packages
install_packages () {
  # Check if the 'sensors' command is available on the system
  if ! command -v sensors &> /dev/null; then
    # If the 'sensors' command is not available, prompt the user to install lm-sensors
    read -p "lm-sensors is not installed. Would you like to install it? (y/n) " choice
    case "$choice" in
      y|Y )
        # If the user chooses to install lm-sensors, update the package list and install the package
        apt-get update
        apt-get install lm-sensors
        ;;
      n|N )
        # If the user chooses not to install lm-sensors, exit the script with a zero status code
        echo "Decided to not install lm-sensors. The mod cannot run without"
        exit 0
        ;;
      * )
        # If the user enters an invalid input, print an error message and exit the script with a non-zero status code
        echo "Invalid input. Exiting..."
        exit 1
        ;;
    esac
  fi
}

# Call the 'install_packages' function to check if lm-sensors is installed and install it if necessary
install_packages


# Function to install the modification
function install_mod {
  # Create backup of original files
  mkdir -p $backuplocation

  # Add new line to Nodes.pm file
  if [[ -z $(cat $nodespm | grep -e "$res->{thermalstate}") ]]; then
    # Create backup of original file
    cp "$nodespm" "$backuplocation/Nodes.pm.$timestamp"
    echo "Backup of $nodespm saved to $backuplocation/Nodes.pm.$timestamp"

    sed -i '/my $dinfo = df('\''\/'\'', 1);/i\'$'\t''$res->{thermalstate} = `sensors -j`;\n'$'\t''$res->{thermalstate2} = `sensors -j`;\n' "$nodespm"
    echo "Added thermalstate to $nodespm"
  else
    echo "Thermalstate already added to $nodespm"
  fi

  # Add new item to the items array in PVE.node.StatusView
  if [[ -z $(cat "$pvemanagerlib" | grep -e "itemId: 'thermal'") ]]; then
    # Create backup of original file
    cp "$pvemanagerlib" "$backuplocation/pvemanagerlib.js.$timestamp"
    echo "Backup of $pvemanagerlib saved to $backuplocation/pvemanagerlib.js.$timestamp"
    
    # Expand space in StatusView
    sed -i "/Ext.define('PVE\.node\.StatusView'/,/\},/ {
      s/\(bodyPadding:\) '[^']*'/\1 '20 15 20 15'/
      s/\(height:\) [0-9]\+/\1 360/}" "$pvemanagerlib"

    echo "Expanded space in $pvemanagerlib"

    sed -i "/^Ext.define('PVE.node.StatusView',/ {
      :a;
      /items:/!{N;ba;}
      :b;
      /swap.*},/!{N;bb;}
      a\
      \\
        {\n\
            itemId: 'thermal',\n\
            colspan: 1,\n\
            printBar: false,\n\
            title: gettext('CPU Thermal State'),\n\
            iconCls: 'fa fa-fw fa-thermometer-half',\n\
            textField: 'thermalstate',\n\
            renderer: function(value){\n\
              let objValue = JSON.parse(value);\n\
              let core0 = objValue[\"k10temp-pci-00c3\"][\"Tctl\"][\"temp1_input\"];\n\
              let core1 = objValue[\"k10temp-pci-00c3\"][\"Tccd1\"][\"temp3_input\"];\n\
              let core2 = objValue[\"k10temp-pci-00c3\"][\"Tccd2\"][\"temp4_input\"];\n\
              return \`CPU Temp: \$\{core0\} C | CCD1 Temp: \$\{core1\} C | CCD2 Temp: \$\{core2\} C\`\n\
            }\n\
        },\n\
        {\n\
            itemId: 'thermal2',\n\
            colspan: 1,\n\
            printBar: false,\n\
            title: gettext('NVME Thermal State'),\n\
            iconCls: 'fa fa-fw fa-thermometer-half',\n\
            textField: 'thermalstate2',\n\
            renderer: function(value){\n\
              let objValue = JSON.parse(value);\n\
              let temp0 = objValue[\"nvme-pci-0100\"][\"Composite\"][\"temp1_input\"];\n\
              return \`NVME: \$\{temp0\} C\`\n\
            }\n\
        },
    }" $pvemanagerlib
    echo "Added new item to the items array in $pvemanagerlib"
  else
    echo "New item already added to items array $pvemanagerlib"
  fi

  # Restart pveproxy
  systemctl restart pveproxy
}

# Function to uninstall the modification
function uninstall_mod {
  # Find the latest Nodes.pm file using the find command
  latest_Nodes_pm=$(find "$backuplocation" -name "Nodes.pm.*" -type f -printf '%T+ %p\n' 2>/dev/null | sort -r | head -n 1 | awk '{print $2}')

  if [ -z "$latest_Nodes_pm" ]; then
    echo "No Nodes.pm files found"
    exit 1
  fi

  # Remove the latest Nodes.pm file
  echo cp "$latest_Nodes_pm" "$nodespm"
  echo "Copied latest backup to $nodespm"

  # Find the latest pvemanagerlib file using the find command
  latest_pvemanagerlib_js=$(find "$backuplocation" -name "pvemanagerlib.js.*" -type f -printf '%T+ %p\n' 2>/dev/null | sort -r | head -n 1 | awk '{print $2}')

  if [ -z "$latest_pvemanagerlib_js" ]; then
          echo "No latest_pvemanagerlib_js files found"
          exit 1
  fi

  # Remove the latest Nodes.pm file
  echo cp "$latest_pvemanagerlib_js" "$pvemanagerlib"
  echo "Copied latest backup to $pvemanagerlib"

  # Restart pveproxy
  systemctl restart pveproxy
}

# If no arguments were provided or all arguments have been processed, print the usage message
if [[ $# -eq 0 ]]; then
	usage
fi

# Process the arguments using a while loop and a case statement
while [[ $# -gt 0 ]]; do
  case "$1" in
    install)
      echo "Installing the mod..."
      install_packages
      install_mod
      ;;
    uninstall)
      echo "Uninstalling the mod..."
      uninstall_mod
      ;;
    *)
      usage
      ;;
  esac
  shift
done

echo ""
exit 0
