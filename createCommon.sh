# createCommon.sh
# 
# Common functionality for the Image creation process.
# sourced in by the various SIU scripts
#
# Copyright © 2007-2017 Apple Inc. All rights reserved.


##
# Using dscl, create a user account
##
AddLocalUser()
{
	# $1 volume whose local node database to modify
	# $2 long name
	# $3 short name
	# $4 isAdminUser key
	# $5 password data
	# $6 password hint
	# $7 user picture path
	# $8 Language string
	# $9 autologin key

	local databasePath="/Local/Default/Users/${3}"
	local targetVol="${1}"

	# Find a free UID between 501 and 599
	for ((i=501; i<600; i++)); do
		output=`/usr/bin/dscl -f "${targetVol}/var/db/dslocal/nodes/Default" localonly -search /Local/Default/Users UniqueID $i`
		# If there is already an account dscl returns it, so we're looking for an empty return value.
		if [ "$output" == "" ]; then
			break
		fi
	done

	# Create the user record
	/usr/bin/dscl -f "${targetVol}/var/db/dslocal/nodes/Default" localonly -create $databasePath
	if [ $? != 0 ]; then
		echo "Failed to create '${databasePath}'."
		return 1
	fi

	# Add long name
	/usr/bin/dscl -f "${targetVol}/var/db/dslocal/nodes/Default" localonly -append $databasePath RealName "${2}"
	if [ $? != 0 ]; then
		echo "Failed to set the RealName."
		return 1
	fi

	# Set up the users group information
	/usr/bin/dscl -f "${targetVol}/var/db/dslocal/nodes/Default" localonly -append $databasePath PrimaryGroupID 20
	if [ $? != 0 ]; then
		echo "Failed to set the PrimaryGroupID."
		return 1
	fi

	# Add some additional stuff if the user is an admin
	if [ "${4}" == 1 ]; then 
		/usr/bin/dscl -f "${targetVol}/var/db/dslocal/nodes/Default" localonly -append "/Local/Default/Groups/admin" GroupMembership "${3}"
		if [ $? != 0 ]; then
			echo "Failed to add the user to the admin group."
			return 1
		fi

		/usr/bin/dscl -f "${targetVol}/var/db/dslocal/nodes/Default" localonly -append "/Local/Default/Groups/_appserveradm" GroupMembership "${3}"
		if [ $? != 0 ]; then
			echo "Failed to add the user to the _appserveradm group."
			return 1
		fi

		/usr/bin/dscl -f "${targetVol}/var/db/dslocal/nodes/Default" localonly -append "/Local/Default/Groups/_appserverusr" GroupMembership "${3}"
		if [ $? != 0 ]; then
			echo "Failed to add the user to the _appserverusr group."
			return 1
		fi
	fi

	# Add UniqueID
	/usr/bin/dscl -f "${targetVol}/var/db/dslocal/nodes/Default" localonly -append $databasePath UniqueID ${i}
	if [ $? != 0 ]; then
		echo "Failed to set the UniqueID."
		return 1
	fi

	# Add Home Directory entry
	/usr/bin/dscl -f "${targetVol}/var/db/dslocal/nodes/Default" localonly -append $databasePath NFSHomeDirectory /Users/${3}
	if [ $? != 0 ]; then
		echo "Failed to set the NFSHomeDirectory."
	fi

	if [ "${6}" != "" ]; then 
		/usr/bin/dscl -f "${targetVol}/var/db/dslocal/nodes/Default" localonly -append $databasePath AuthenticationHint "${6}"
		if [ $? != 0 ]; then
			echo "Failed to set the AuthenticationHint."
			return 1
		fi
	fi

	/usr/bin/dscl -f "${targetVol}/var/db/dslocal/nodes/Default" localonly -append $databasePath picture "${7}"
	if [ $? != 0 ]; then
		echo "Failed to set the picture."
		return 1
	fi

	/usr/bin/dscl -f "${targetVol}/var/db/dslocal/nodes/Default" localonly -passwd $databasePath "${5}"
	if [ $? != 0 ]; then
		echo "Failed to set the passwd."
		return 1
	fi

	# Add shell
	/usr/bin/dscl -f "${targetVol}/var/db/dslocal/nodes/Default" localonly -append $databasePath UserShell "/bin/bash"
	if [ $? != 0 ]; then
		echo "Failed to set the UserShell."
		return 1
	fi

	# Create Home directory
	if [ -e "/System/Library/User Template/${8}.lproj/" ]; then
		/usr/bin/ditto "/System/Library/User Template/${8}.lproj/" "${targetVol}/Users/${3}"
	else
		/usr/bin/ditto "/System/Library/User Template/English.lproj/" "${targetVol}/Users/${3}"
	fi
	if [ $? != 0 ]; then
		echo "Failed to copy the User Template."
		return 1
	fi

	#inhibit MiniBuddy from running for this user
	/usr/bin/touch "${targetVol}/Users/${3}/.skipbuddy"

	/usr/sbin/chown -R $i:20 "${targetVol}/Users/${3}"
	if [ $? != 0 ]; then
		echo "Failed to set ownership on the User folder."
		return 1
	fi

	# if the user is to be automatically logged in, put the user name into the loginwindow prefs
	if [ "${9}" == 1 ]; then
		/usr/libexec/PlistBuddy -c "Delete :autoLoginUser" "${targetVol}/Library/Preferences/com.apple.loginwindow.plist" > /dev/null 2>&1
		/usr/libexec/PlistBuddy -c "Delete :autoLoginUserUID" "${targetVol}/Library/Preferences/com.apple.loginwindow.plist" > /dev/null 2>&1

		/usr/libexec/PlistBuddy -c "Add :autoLoginUser string ${3}" "${targetVol}/Library/Preferences/com.apple.loginwindow.plist" > /dev/null 2>&1
	fi
}


##
# Copies a list of files (full paths contained in the file at $1) from source to the path specified in $2
##
CopyEntriesFromFileToPath()
{
	local theFile="$1"
	local theDest="$2"
	local opt=""

	if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
		opt="-v"
	fi

	while read FILE
	do
		if [ -e "${FILE}" ]; then
			if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
				echo "Copying ${FILE}."
			fi

			# can't use basename in the install environment, use bash instead
			/usr/bin/ditto $opt "${FILE}" "${theDest}/${FILE##*/}" || return 1
		fi
	done < "${theFile}"

	return 0
}


##
# Copies a list of packages (full path, destination pairs contained in the file at $1) from source to .../System/Installation/Packages/
##
CopyPackagesWithDestinationsFromFile()
{
	local theFile="${1}"
	local tempDir=`dirname "${1}"`
	local opt=""

	if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
		opt="-v"
	fi

	while read FILE
	do
		if [ -e "${FILE}" ]; then
			# can't use basename in the install environment, use bash instead
			local leafName=${FILE##*/}

			if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
				echo "Copying ${FILE}."
			fi

			read SUB_PATH
			if [ "${SUB_PATH}" == "/" ]; then
				SUB_PATH=""
			fi
			/usr/bin/ditto $opt "${FILE}" "${mountPoint}/Packages/${SUB_PATH}${leafName}" || return 1

			# write out the path to a file we can source from later
			echo "/System/Installation/Packages/${SUB_PATH}${leafName}" >> ${tempDir}/postRestorePackages.txt
		fi
	done < "${theFile}"

	return 0
}


##
# Create an 'Extras' directory in the 'Packages' directory supplied in ${1}
##
CreateExtrasDirectory()
{
	local extrasDir="${1}/Extras"

	# Create the Extras directory if it doesn't exist
	if [ ! -d "${extrasDir}" ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			echo "Creating 'Extras' directory in '${1}'"
		fi

		/bin/mkdir "${extrasDir}"
		# Make sure the perms are correct
		/usr/sbin/chown root:wheel "${extrasDir}"
		/bin/chmod 755 "${extrasDir}"
	fi
}


##
# Create an installer package in ${1} wrapping the supplied script ${2}
##
CreateInstallPackageForScript()
{
	local tempDir="$1"
	local scriptPath="$2"
	local scriptName=${scriptPath##*/}
	local opt=""

	if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
		echo "Create installer for script ${scriptName}"
		opt="-v"
	fi

	# shouldn't exist on entry...
	if [ -e "${tempDir}/emptyDir" ]; then
		/bin/rm -rf "${tempDir}/emptyDir"
	fi

	# make a directory to work in
	/bin/mkdir $opt "${tempDir}/emptyDir" || return 1
	/bin/cp $opt "${scriptPath}" "${tempDir}/emptyDir/postinstall" || return 1

	/usr/bin/pkgbuild --scripts "${tempDir}/emptyDir" --nopayload --identifier "com.apple.SystemImageUtility.${scriptName}" "${tempDir}/${scriptName}.inner.pkg" || return 1
	/usr/bin/productbuild --package "${tempDir}/${scriptName}.inner.pkg" "${tempDir}/${scriptName}.pkg" || return 1

	# clean up
	/bin/rm -r "${tempDir}/emptyDir" || return 1

	return 0
}


##
# Validate or create the requested directory
##
CreateOrValidatePath()
{
	local targetDir="$1"

	if [ ! -d "${targetDir}" ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			echo "Creating working path at ${targetDir}"
		fi
		/bin/mkdir -p "${targetDir}" || return 1
	fi
}


##
# If any exist, apply any user accounts
##
CreateUserAccounts()
{
	# $1 temporary directory
	# $2 volume whose local node database to modify

	local tempDir="${1}"
	local count="${#userFullName[*]}"
	local targetVol="${2}"
	local opt=""

	if [ $count -gt 0 ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			echo "Adding $count user account(s) to the image"
		fi

		for ((index=0; index<$count; index++)); do
			if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
				echo "Adding user ${userFullName[$index]}"
			fi

			#lay down user here
			AddLocalUser "${targetVol}" "${userFullName[$index]}" "${userUnixName[$index]}" "${userIsAdmin[$index]}" "${userPassword[$index]}" "${userPassHint[$index]}" "${userImagePath[$index]}" "${userLanguage[$index]}" "${autoLoginUser[$index]}"
			if [ $? != 0 ]; then
				echo "Failed to create the User '${userUnixName[$index]}'."
				return 1
			fi
		done

		# if it exists, put the autologin password in place
		if [ -e "${tempDir}/kcpassword" ]; then
			if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
				echo "Installing autoLogin password file"
				opt="-v"
			fi
			/usr/bin/ditto $opt "${tempDir}/kcpassword" "${targetVol}/etc/kcpassword" || return 1
			/bin/chmod 600 "${targetVol}/etc/kcpassword"
		fi

		# "touch"
		/usr/bin/touch "${targetVol}/private/var/db/.AppleSetupDone" 
		/usr/bin/touch "${targetVol}/Library/Receipts/.SetupRegComplete"

	fi
}


##
# retry the hdiutil detach until we either time out or it succeeds
##
retry_hdiutil_detach() 
{
	local mount_point="${1}"
	local tries=0
	local forceAt=0
	local limit=24
	local opt=""

	forceAt=$(($limit - 1))
	while [ $tries -lt $limit ]; do
		tries=$(( tries + 1 ))
		/bin/sleep 5
		echo "Attempting to detach the disk image again..."
		/usr/bin/hdiutil detach "${mount_point}" $opt
		if [ $? -ne 0 ]; then
			# Dump a list of any still open files on the mountPoint
			if [ "${scriptsDebugKey}" == "DEBUG" ]; then
				/usr/sbin/lsof +fg "${mount_point}"
			fi

			if [ $tries -eq $forceAt ]; then
				echo "Failed to detach disk image at '${mount_point}' normally, adding -force."
				opt="-force"
			fi

			if [ $tries -eq $limit ]; then
				echo "Failed to detach disk image at '${mount_point}'."
				exit 1
			fi
		else
			tries=$limit
		fi
	done
}
 

##
# Create the dyld shared cache files
##
DetachAndRemoveMount()
{
	local theMount="${1}"
	local mountLoc=`/sbin/mount | grep "${theMount}"`

	if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
		echo "Detaching disk image"

		# Dump a list of any still open files on the mountPoint
		if [ "${scriptsDebugKey}" == "DEBUG" ]; then
			/usr/sbin/lsof +fg "${theMount}"
		fi
	fi

	# Finally detach the mount (if it's actually mounted) and dispose the mountPoint directory
	if [ "${mountLoc}" != "" ]; then
		/usr/bin/hdiutil detach "${theMount}" || retry_hdiutil_detach "${theMount}" || return 1
	fi
	/bin/rmdir "${theMount}" || return 1

	return 0
}


##
# If the pieces exist, enable remote access for the shell image
##
EnableRemoteAccess()
{
	local srcVol="${1}"
	local opt=""

	if [ -e "${srcVol}/usr/lib/pam/pam_serialnumber.so.2" ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			echo "Enabling shell image remote access support"
			opt="-v"
		fi

		# install some things (again which aren't part of BaseSystem) needed for remote ASR installs
		/usr/bin/ditto $opt "${srcVol}/usr/lib/pam/pam_serialnumber.so.2" "${mountPoint}/usr/lib/pam/pam_serialnumber.so.2" || return 1

		if [ -e "${srcVol}/usr/sbin/installer" ]; then
			/usr/bin/ditto $opt "${srcVol}/usr/sbin/installer" "${mountPoint}/usr/sbin/installer" || return 1
		fi

		# copy the sshd config and add our keys to the end of it
		if [ -e "${srcVol}/etc/sshd_config" ]; then
			/bin/cat "${srcVol}/etc/sshd_config" - > "${mountPoint}/etc/sshd_config" << END

HostKey /private/var/tmp/ssh_host_key
HostKey /private/var/tmp/ssh_host_rsa_key
HostKey /private/var/tmp/ssh_host_dsa_key
END
		fi
	fi

	return 0
}


##
# If it exists, install the sharing names and/or directory binding support to the install image
##
HandleNetBootClientHelper()
{
	local tempDir="${1}"
	local targetVol="${2}"
	local opt=""

	if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
		opt="-v"
	fi

	if [ -e "${tempDir}/bindingNames.plist" ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			echo "Installing Directory Service binding information"
		fi

		/usr/bin/ditto $opt "${tempDir}/bindingNames.plist" "${targetVol}/etc/bindingNames.plist" || return 1
		/usr/sbin/chown root:wheel "${targetVol}/etc/bindingNames.plist"
		/bin/chmod 644 "${targetVol}/etc/bindingNames.plist"
	fi

	if [ -e "${tempDir}/sharingNames.plist" ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			echo "Installing Sharing Names support"
		fi

		/usr/bin/ditto $opt "${tempDir}/sharingNames.plist" "${targetVol}/etc/sharingNames.plist" || return 1
		/usr/sbin/chown root:wheel "${targetVol}/etc/sharingNames.plist"
		/bin/chmod 644 "${targetVol}/etc/sharingNames.plist"
	fi

	if [ -e "${tempDir}/NetBootClientHelper" ]; then
		/usr/bin/ditto $opt "${tempDir}/NetBootClientHelper" "${targetVol}/usr/sbin/NetBootClientHelper" || return 1
		/usr/sbin/chown root:wheel "${targetVol}/usr/sbin/NetBootClientHelper"
		/bin/chmod 555 "${targetVol}/usr/sbin/NetBootClientHelper"
		/usr/bin/ditto $opt "${tempDir}/com.apple.NetBootClientHelper.plist" "${targetVol}/Library/LaunchDaemons/com.apple.NetBootClientHelper.plist" || return 1
		/usr/sbin/chown root:wheel "${targetVol}/Library/LaunchDaemons/com.apple.NetBootClientHelper.plist"
		/bin/chmod 644 "${targetVol}/Library/LaunchDaemons/com.apple.NetBootClientHelper.plist"

		# finally, make sure it isn't disabled...
		/usr/libexec/PlistBuddy -c "Delete :com.apple.NetBootClientHelper" "${targetVol}/var/db/launchd.db/com.apple.launchd/overrides.plist" > /dev/null 2>&1
	fi

	return 0
}


##
# Copy the necessary boot files directly off the BaseSystem media
##
InstallBaseSystemToNBI()
{
	local baseSystemDMG="${1}"
	local nbiDir="${2}"
	local opt=""

	if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ] ; then
		opt="-v"
		echo "Copying Base System bits to the NBI shell"
	fi

	baseMount=`mktemp -d "/tmp/mnt_bs.XXXXXXXX"`
	/usr/bin/hdiutil attach "${baseSystemDMG}" -noverify -owners on -nobrowse -noautoopen -mountpoint "${baseMount}" -quiet || return 1

	# grab boot.efi
	/bin/cp $opt "${baseMount}/System/Library/CoreServices/boot.efi" "${nbiDir}/i386/booter" || return 1

	# grab the PlatformSupport.plist
	if [ -e "${baseMount}/System/Library/CoreServices/PlatformSupport.plist" ]; then
		/bin/cp $opt "${baseMount}/System/Library/CoreServices/PlatformSupport.plist" "${nbiDir}/i386/PlatformSupport.plist" || return 1
	else
		# old school... on the install volume
		installSource=`dirname "${baseSystemDMG}"`
		/bin/cp $opt "${installSource}/System/Library/CoreServices/PlatformSupport.plist" "${nbiDir}/i386/PlatformSupport.plist" || return 1
	fi

	# grab the kernelcache
	if [ -e "${baseMount}/System/Library/PrelinkedKernels/prelinkedkernel" ]; then
		/bin/cp $opt "${baseMount}/System/Library/PrelinkedKernels/prelinkedkernel" "${nbiDir}/i386/x86_64/kernelcache" || return 1
	else
		/bin/cp $opt "${baseMount}/System/Library/Caches/com.apple.kext.caches/Startup/kernelcache" "${nbiDir}/i386/x86_64/kernelcache" || return 1
	fi

	# grab the wifi firmware
	if [ -d "${baseMount}/usr/share/firmware/wifi" ]; then
		/bin/cp -R $opt "${baseMount}/usr/share/firmware/wifi" "${nbiDir}/i386/wifi" || return 1
	fi

	# create a relevant com.apple.Boot.plist
	/usr/libexec/PlistBuddy -c "add :'Kernel Flags' string 'root-dmg=file:///BaseSystem.dmg'" "${nbiDir}/i386/com.apple.Boot.plist" > /dev/null 2>&1

	# Clean up
	/usr/bin/hdiutil detach "${baseMount}" || retry_hdiutil_detach "${baseMount}" || return 1
	/bin/rmdir "${baseMount}"

	return 0
}


##
# If any exist, install configuration profiles to the install image
##
InstallConfigurationProfiles()
{
	local tempDir="${1}"
	local targetVol="${2}"
	local profilesDir="${targetVol}/var/db/ConfigurationProfiles"

	if [ -e "${tempDir}/configProfiles.txt" ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			echo "Installing Configuration Profiles"
		fi

		/bin/mkdir -p "${profilesDir}/Setup" || return 1
		# Make sure the perms are correct
		/usr/sbin/chown root:wheel "${profilesDir}"
		/bin/chmod 755 "${profilesDir}"
		/usr/sbin/chown root:wheel "${profilesDir}/Setup"
		/bin/chmod 755 "${profilesDir}/Setup"

		CopyEntriesFromFileToPath "${tempDir}/configProfiles.txt" "${profilesDir}/Setup" || return 1

		# Two more necessary tasks
		/bin/rm "${profilesDir}/Setup/.profileSetupDone" > /dev/null 2>&1
		/usr/bin/touch "${profilesDir}/Setup/.profileSetupRetryFailedProfiles"

		# Enable MCX debugging
		if [ 1 == 1 ]; then
			if [ -e "${targetVol}/Library/Preferences/com.apple.MCXDebug.plist" ]; then
				/usr/libexec/PlistBuddy -c "Delete :debugOutput" "${targetVol}/Library/Preferences/com.apple.MCXDebug.plist" > /dev/null 2>&1
				/usr/libexec/PlistBuddy -c "Delete :collateLogs" "${targetVol}/Library/Preferences/com.apple.MCXDebug.plist" > /dev/null 2>&1
			fi

			/usr/libexec/PlistBuddy -c "Add :debugOutput string -2" "${targetVol}/Library/Preferences/com.apple.MCXDebug.plist" > /dev/null 2>&1
			/usr/libexec/PlistBuddy -c "Add :collateLogs string 1" "${targetVol}/Library/Preferences/com.apple.MCXDebug.plist" > /dev/null 2>&1
		fi

		# Set a flag so the NetRestore code doesn't stash the profiles for post ASR installation
		/usr/bin/touch "${tempDir}/configProfilesWereInstalled"
	fi
}


##
# If any exist, install additional packages and/or scripts after completing the OS Install
##
InstallExtraPackagesAndScripts()
{
	local tempDir="${1}"
	local targetVol="${2}"
	local trust="-allowUntrusted"

	# install any additional packages that were requested
	if [ -e "${tempDir}/installPackages.txt" ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			echo "Installing Additional Packages"
		fi

		while read FILE
		do
			if [ -e "${FILE}" ]; then
				/usr/sbin/installer $trust -pkg "${FILE}" -target "${targetVol}" || return 1
			fi
		done < "${tempDir}/installPackages.txt"
	fi

	# install any scripts that were requested
	if [ -e "${tempDir}/installScripts.txt" ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			echo "Installing Additional Scripts"
		fi

		while read FILE
		do
			if [ -e "${FILE}" ]; then
				# make an installer package out of the script
				CreateInstallPackageForScript "$tempDir" "${FILE}" || return 1

				# use the installer to post install the script
				# can't use basename in the install environment, use bash instead
				/usr/sbin/installer $trust -pkg "${tempDir}/${FILE##*/}.pkg" -target "${targetVol}" || return 1
			fi
		done < "${tempDir}/installScripts.txt"
	fi
}


##
# If any exist, install language hint files
##
InstallLanguageHints()
{
	local tempDir="${1}"
	local targetVol="${2}"
	local opt=""

	if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
		echo "Installing language hint files"
		opt="-v"
	fi

	if [ -e "${tempDir}/CDIS.custom" ]; then
		/usr/bin/ditto $opt "${tempDir}/CDIS.custom" "${targetVol}/var/log/CDIS.custom" || return 1
	fi

	if [ -e "${tempDir}/GlobalPreferences.plist" ]; then
		plutil -convert binary1 "${tempDir}/GlobalPreferences.plist" || return 1
		/usr/bin/ditto $opt "${tempDir}/GlobalPreferences.plist" "${targetVol}/Library/Preferences/.GlobalPreferences.plist" || return 1
	fi
}


##
# Converts a list of scripts (full paths contained in the file at $1) into packages in $3
##
InstallScriptsFromFile()
{
	local tempDir="${1}"
	local theFile="${2}"
	local targetDir="${3}"
	local opt=""

	if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then 
		echo "Converting scripts into install packages"
		opt="-v"
	fi

	while read FILE
	do
		if [ -e "${FILE}" ]; then
			# make an installer package out of the script
			CreateInstallPackageForScript "$tempDir" "${FILE}" || return 1

			# can't use basename in the install environment, use bash instead
			local leafName=${FILE##*/}

			# copy the resulting package to the Packages directory
			/usr/bin/ditto $opt "${tempDir}/${leafName}.pkg" "${targetDir}/${leafName}.pkg" || return 1

			# write out the path to a file we can source from later
			echo "/System/Installation/Packages/${leafName}.pkg" >> ${tempDir}/postRestorePackages.txt

			# clean up
			/bin/rm -r "${tempDir}/${leafName}.pkg"
		fi
	done < "${theFile}"

	return 0
}


##
# Prepare the source by deleting stuff we don't want to copy if sourcing a volume
##
PostFlightDestination()
{
	local tempDir="${1}"
	local destDir="${2}"
	local opt=""

	if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
		echo "Performing post install cleanup"
		opt="-v"
	fi

	# delete the DS indices to force reindexing...
	if [ -e "${mountPoint}/var/db/dslocal/indices/Default/index" ]; then
		/bin/rm $opt "${mountPoint}/var/db/dslocal/indices/Default/index"
	fi

	# detach the disk and remove the mount folder
	DetachAndRemoveMount "${mountPoint}"
	if [ $? != 0 ]; then
		echo "Failed to detach and clean up the mount at '${mountPoint}'."
		return 1
	fi

	echo "Correcting permissions. ${ownershipInfoKey} $destDir"
	/usr/sbin/chown -R "${ownershipInfoKey}" "$destDir"
}


##
# Prepare the source by deleting stuff we don't want to copy if sourcing a volume
##
PreCleanSource()
{
	local srcVol="$1"
	local opt=""

	if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
		opt="-v"
	fi

	if [ -e "$srcVol/private/var/vm/swapfile*" ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			echo "Removing swapfiles on $1"
		fi
		/bin/rm $opt "$srcVol/private/var/vm/swapfile*"
	fi

	if [ -e "$srcVol/private/var/vm/sleepimage" ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			echo "Removing sleepimage on $1"
		fi
		/bin/rm $opt "$srcVol/private/var/vm/sleepimage"
	fi

	if [ -d "$srcVol/private/tmp" ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			echo "Cleaning out /private/tmp on $1"
		fi
		/bin/rm -r $opt "$srcVol/private/tmp/*" > /dev/null 2>&1
	fi

	if [ -d "$srcVol/private/var/tmp" ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			echo "Cleaning out /private/var/tmp on $1"
		fi
		/bin/rm -r $opt "$srcVol/private/var/tmp/*" > /dev/null 2>&1
	fi

	if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
		echo "Cleaning out devices and volumes on $1"
	fi
	if [ -d "$srcVol/Volumes" ]; then
		/bin/rm -r $opt "$srcVol/Volumes/*" > /dev/null 2>&1
	fi
	if [ -d "$srcVol/dev" ]; then
		/bin/rm $opt "$srcVol/dev/*" > /dev/null 2>&1
	fi
	if [ -d "$srcVol/private/var/run" ]; then
		/bin/rm -r $opt "$srcVol/private/var/run/*" > /dev/null 2>&1
	fi
}


##
# If it exists, install the partitioning application and data onto the install image
##
ProcessAutoPartition()
{
	local tempDir="$1"
	local opt=""
	local targetDir=""

	if [ -e "$tempDir/PartitionInfo.plist" ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			opt="-v"
		fi

		# Determine if this is an install source, or a restore source
		if [ -d "${mountPoint}/Packages" ]; then
			if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
				echo "Installing Partitioning application and data to install image"
			fi
			targetDir="${mountPoint}/Packages"
		elif [ -d "${mountPoint}/System/Installation/Packages" ]; then
			if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
				echo "Installing Partitioning application and data to restore image"
			fi
			targetDir="${mountPoint}/System/Installation/Packages"
		else
			echo "There doesn't appear to be either an install or restore source mounted at ${mountPoint}"
			return 1
		fi

		# Create the Extras directory if it doesn't exist
		CreateExtrasDirectory "${targetDir}"
		targetDir="${targetDir}/Extras"

		/usr/bin/ditto $opt "$tempDir/PartitionInfo.plist" "${targetDir}/PartitionInfo.plist" || return 1
		/usr/bin/ditto $opt "$tempDir/AutoPartition.app" "${targetDir}/AutoPartition.app" || return 1
		/usr/bin/ditto $opt "$tempDir/rc.imaging" "${targetDir}/rc.imaging" || return 1
	fi

	return 0
}


##
# If it exists, install the minstallconfig.xml onto the install image
##
ProcessMinInstall()
{
	local tempDir="$1"
	local opt=""
	local targetDir="${mountPoint}/Packages"

	if [ -e "$tempDir/minstallconfig.xml" ]; then
		if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
			echo "Installing minstallconfig.xml to install image"
			opt="-v"
		fi

		# Create the Extras directory if it doesn't exist
		CreateExtrasDirectory "${targetDir}"
		targetDir="${targetDir}/Extras"

		/usr/bin/ditto $opt "$tempDir/minstallconfig.xml" "${targetDir}/minstallconfig.xml" || return 1
		/usr/sbin/chown root:wheel "${targetDir}/minstallconfig.xml"
		/bin/chmod 644 "${targetDir}/minstallconfig.xml"
	fi

	return 0
}


##
# Copy an item, showing progress as determined by the remaining space on the target
#
# $1 source item
# $2 destination
# $3 to suppress initial/final state logging
##
ProgressDitto()
{
	local opt=""
	local pct="0"
	local retVal=0

	# Disable any echoing to reduce spew
	if [ "${scriptsDebugKey}" == "VERBOSE" -o "${scriptsDebugKey}" == "DEBUG" ]; then
		set +xv
		opt="-v"
	fi

	# Run the copy in a subshell so we can watch the progress
	tmp1=$(mktemp)
	( /usr/bin/ditto $opt "${1}" "${2}"; echo $? > "$tmp1" ) &
	copyProcess=$!

	if [ -z "${3}" ]; then
		# Send an inital state update
		echo "PERCENT:0%"
	fi

	# Run a disk free space check, echoing a format we scrape for in the Agent
	while : ; do
		if ps -p $copyProcess > /dev/null ; then
			pct=`/bin/df "${mountPoint}" | grep "${mountPoint}" | awk '{print $5}' | cut -d "%" -f1`
			echo "PERCENT:$pct%"
			sleep 1
		else
			break
		fi
	done

	if [ -z "${3}" ]; then
		# Send a final state update
		echo "PERCENT:100%"
	fi

	# Retrieve the termination value from the copy
	read retVal < "$tmp1"
	if [ "$retVal" != 0 ]; then
		echo "Copy from '${1}' to '${2}' failed."
	fi

	# Clean up the output file
	/bin/rm "$tmp1"

	# Reset any echoing back to the original value
	if [ "${scriptsDebugKey}" == "VERBOSE" ]; then
		set -x +v
	elif [ "${scriptsDebugKey}" == "DEBUG" ]; then
		set -xv
	fi

	return $retVal
}

