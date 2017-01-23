#!/bin/sh

source /etc/utopia/service.d/log_capture_path.sh
source /fss/gw/etc/utopia/service.d/log_env_var.sh

if [ -f /etc/device.properties ]
then
    source /etc/device.properties
fi

XCONF_LOG_FILE_NAME=xconf.txt.0
XCONF_LOG_FILE_PATHNAME=${LOG_PATH}/${XCONF_LOG_FILE_NAME}
XCONF_LOG_FILE=${XCONF_LOG_FILE_PATHNAME}

CURL_PATH=/fss/gw/usr/bin
interface=erouter0
BIN_PATH=/fss/gw/usr/bin
REBOOT_WAIT="/tmp/.waitingreboot"
DOWNLOAD_INPROGRESS="/tmp/.downloadingfw"
#GLOBAL DECLARATIONS
image_upg_avl=0

#
# release numbering system rules
#

# 5 part release numbering scheme where the five parts consisted of 
#+ "Major Rev"."Minor Rev"."Internal Rev". "Patch Level"."SPIN".

# 1.Major  Rev and Minor Rev will follow the matching RDKB version.
# 2.Any field which formerly contained  a zero (except for "Minor Rev") will be suppressed in the build number as well as the preceding "."
# 3.The "Spin" field will be  preceded by  "s"  for spin,  rather than a ".'  ie s4
# 4.The Spin field is always in the range of 1-x; Since it is  never 0, this field is always present.
# 5.The "Patch Level" field will be preceded by  "p" (lower case)  for patch rather than a "." . ie p2
# 6.The patch level field is in the range of 0-x.  If the patch level value is zero, the entire field will be suppressed including the leading "p". 
# 7."Internal Rev" can be in the range of 0-x, When the value of Internal Rev is 0, it will be suppressed, including the preceding "."
# 8.Initial State: We will be reverting the Internal Rev to Zero. This will allow us to suppress the field initially
# 9. The "Patch level" filed if present will always preceed "Spin" field.

# example build release numbers
# 1.22s55555                    spin_on_minor           3
# 1.22p4444s55555               spin_on_patch           1
# 1.22.333s55555                spin_on_internal        2
# 1.22.333p4444s55555           spin_on_patch           3
# 

# param1 : cur_rel_num param2 : upg_rel_num
# assumption : 
#       cur and upg firmware version are validated against release numbering system rules
#       no assumption is made about the length of the fields
# spin_on : 1 spin_on_patch 2 spin_on_internal 3 spin_on_minor


# Get currrent firmware in th eunit
getCurrentFw()
{
 currentfw=""
 # Check the location of version.txt file
 if [ -f "/fss/gw/version.txt" ]
 then
    currentfw=`cat /fss/gw/version.txt | grep image | cut -f2 -d=`
 elif [ -f "/version.txt" ]
 then
    if [ "$currentfw" = "" ]
	then
        currentfw=`cat /version.txt | grep image | cut -f2 -d=`
	fi
 fi
 echo $currentfw
}

checkFirmwareUpgCriteria()
{
    image_upg_avl=0;

    # Retrieve current firmware version
    currentVersion=`getCurrentFw`

    #Comcast signed firmware images are represented in lower case and vendor signed images are represented in upper case.
    #In order to avoid confusion in string comparison, converting both currentVersion and firmwareVersion to lower case.
    currentVersion=`echo $currentVersion | tr '[A-Z]' '[a-z]'`
    firmwareVersion=`echo $firmwareVersion | tr '[A-Z]' '[a-z]'`


    echo_t "XCONF SCRIPT : CurrentVersion : $currentVersion"
    echo_t "XCONF SCRIPT : UpgradeVersion : $firmwareVersion"

    echo_t "XCONF SCRIPT : CurrentVersion : $currentVersion" >> $XCONF_LOG_FILE
    echo_t "XCONF SCRIPT : UpgradeVersion : $firmwareVersion" >> $XCONF_LOG_FILE

    if [ "$currentVersion" != "" ] && [ "$firmwareVersion" != "" ];then
		if [ "$currentVersion" == "$firmwareVersion" ]; then
			echo_t "XCONF SCRIPT : Current image ("$currentVersion") and Requested imgae ("$firmwareVersion") are same. No upgrade/downgrade required"
			echo_t "XCONF SCRIPT : Current image ("$currentVersion") and Requested imgae ("$firmwareVersion") are same. No upgrade/downgrade required">> $XCONF_LOG_FILE
			image_upg_avl=0
		else
			echo_t "XCONF SCRIPT : Current image ("$currentVersion") and Requested imgae ("$firmwareVersion") are different. Processing Upgrade/Downgrade"
			echo_t "XCONF SCRIPT : Current image ("$currentVersion") and Requested imgae ("$firmwareVersion") are different. Processing Upgrade/Downgrade">> $XCONF_LOG_FILE
			image_upg_avl=1
		fi
	else
		echo_t "XCONF SCRIPT : Current image ("$currentVersion") Or Requested imgae ("$firmwareVersion") returned NULL. No Upgrade/Downgrade"
		echo_t "XCONF SCRIPT : Current image ("$currentVersion") Or Requested imgae ("$firmwareVersion") returned NULL. No Upgrade/Downgrade">> $XCONF_LOG_FILE
		image_upg_avl=0
	fi
}

# Check if a new image is available on the XCONF server
getFirmwareUpgDetail()
{
    # The retry count and flag are used to resend a 
    # query to the XCONF server if issues with the 
    # respose or the URL received
    xconf_retry_count=1
    retry_flag=1

    # Set the XCONF server url read from /tmp/Xconf 
    # Determine the env from $type

    #s16 : env=`cat /tmp/Xconf | cut -d "=" -f1`
    env=$type
    xconf_url=`cat /tmp/Xconf | cut -d "=" -f2`
    
    # If an /tmp/Xconf file was not created, use the default values
    if [ ! -f /tmp/Xconf ]; then
        echo_t "XCONF SCRIPT : ERROR : /tmp/Xconf file not found! Using defaults"
        echo_t "XCONF SCRIPT : ERROR : /tmp/Xconf file not found! Using defaults" >> $XCONF_LOG_FILE
        env="PROD"
        xconf_url="https://xconf.xcal.tv/xconf/swu/stb/"
    fi

    echo_t "XCONF SCRIPT : env is $env"
    echo_t "XCONF SCRIPT : xconf url  is $xconf_url"

    # Check with the XCONF server if an update is available 
    while [ $xconf_retry_count -le 3 ] && [ $retry_flag -eq 1 ]
    do

        echo_t "**RETRY is $xconf_retry_count and RETRY_FLAG is $retry_flag**" >> $XCONF_LOG_FILE
        
        # White list the Xconf server url
        #echo "XCONF SCRIPT : Whitelisting Xconf Server url : $xconf_url"
        #echo "XCONF SCRIPT : Whitelisting Xconf Server url : $xconf_url" >> $XCONF_LOG_FILE
        #/etc/whitelist.sh "$xconf_url"
        
        # Perform cleanup by deleting any previous responses
        rm -f /tmp/response.txt /tmp/XconfOutput.txt
        firmwareDownloadProtocol=""
        firmwareFilename=""
        firmwareLocation=""
        firmwareVersion=""
        rebootImmediately=""
        ipv6FirmwareLocation=""
        upgradeDelay=""
       
        currentVersion=`getCurrentFw`
		
        MAC=`ifconfig  | grep $interface |  grep -v $interface:0 | tr -s ' ' | cut -d ' ' -f5`
        date=`date`
        modelName=`dmcli eRT getv Device.DeviceInfo.ModelName | grep value | cut -d ":" -f 3 | tr -d ' ' `
        echo_t "XCONF SCRIPT : CURRENT VERSION : $currentVersion" 
        echo_t "XCONF SCRIPT : CURRENT MAC  : $MAC" 
        echo_t "XCONF SCRIPT : CURRENT DATE : $date"  
	echo_t "XCONF SCRIPT : MODEL : $modelName"

        # Query the  XCONF Server
        HTTP_RESPONSE_CODE=`$CURL_PATH/curl --interface $interface -k -w '%{http_code}\n' -d "eStbMac=$MAC&firmwareVersion=$currentVersion&env=$env&model=$modelName&localtime=$date&timezone=EST05&capabilities="rebootDecoupled"&capabilities="RCDL"&capabilities="supportsFullHttpUrl"" -o "/tmp/response.txt" "$xconf_url" --connect-timeout 30 -m 30`
	    
        echo_t "XCONF SCRIPT : HTTP RESPONSE CODE is $HTTP_RESPONSE_CODE" >> $XCONF_LOG_FILE
        # Print the response
        cat /tmp/response.txt
        cat "/tmp/response.txt" >> $XCONF_LOG_FILE

        if [ $HTTP_RESPONSE_CODE -eq 200 ];then
            retry_flag=0
			
	    OUTPUT="/tmp/XconfOutput.txt" 
            cat "/tmp/response.txt" | tr -d '\n' | sed 's/[{}]//g' | awk  '{n=split($0,a,","); for (i=1; i<=n; i++) print a[i]}' | sed 's/\"\:\"/\|/g' | sed -r 's/\"\:(true)($)/\|true/gI' | sed -r 's/\"\:(false)($)/\|false/gI' | sed -r 's/\"\:(null)($)/\|\1/gI' | sed -r 's/\"\:([0-9]+)($)/\|\1/g' | sed 's/[\,]/ /g' | sed 's/\"//g' > $OUTPUT
            
	    firmwareDownloadProtocol=`grep firmwareDownloadProtocol $OUTPUT  | cut -d \| -f2`

            if [ "$firmwareDownloadProtocol" == "http" ];then
                echo_t "XCONF SCRIPT : Download image from HTTP server" >> $XCONF_LOG_FILE
                firmwareLocation=`grep firmwareLocation $OUTPUT | cut -d \| -f2 | tr -d ' '`
            else
                echo_t "XCONF SCRIPT : Download from TFTP server not supported, check XCONF server configurations" >> $XCONF_LOG_FILE
                echo_t "XCONF SCRIPT : Retrying query in 2 minutes" >> $XCONF_LOG_FILE
                
                # sleep for 2 minutes and retry
                sleep 120;

                retry_flag=1
                image_upg_avl=0

                #Increment the retry count
                xconf_retry_count=$((xconf_retry_count+1))

                continue
            fi

            firmwareFilename=`grep firmwareFilename $OUTPUT | cut -d \| -f2`
    	    firmwareVersion=`grep firmwareVersion $OUTPUT | cut -d \| -f2`
	    ipv6FirmwareLocation=`grep ipv6FirmwareLocation  $OUTPUT | cut -d \| -f2 | tr -d ' '`
	    upgradeDelay=`grep upgradeDelay $OUTPUT | cut -d \| -f2`
            rebootImmediately=`grep rebootImmediately $OUTPUT | cut -d \| -f2`    
                                    
            echo_t "XCONF SCRIPT : Protocol :"$firmwareDownloadProtocol
            echo_t "XCONF SCRIPT : Filename :"$firmwareFilename
            echo_t "XCONF SCRIPT : Location :"$firmwareLocation
            echo_t "XCONF SCRIPT : Version  :"$firmwareVersion
            echo_t "XCONF SCRIPT : Reboot   :"$rebootImmediately
	
            if [ "X"$firmwareLocation = "X" ];then
                echo_t "XCONF SCRIPT : No URL received in /tmp/response.txt" >> $XCONF_LOG_FILE
                retry_flag=1
                image_upg_avl=0

                #Increment the retry count
                xconf_retry_count=$((xconf_retry_count+1))

            else
                echo "$firmwareLocation" > /tmp/.xconfssrdownloadurl
           	# Check if a newer version was returned in the response
            # If image_upg_avl = 0, retry reconnecting with XCONf in next window
            # If image_upg_avl = 1, download new firmware 
                checkFirmwareUpgCriteria  
			fi
		

        # If a response code of 404 was received, exit
        elif [ $HTTP_RESPONSE_CODE -eq 404 ]; then 
            retry_flag=0
            image_upg_avl=0
            echo_t "XCONF SCRIPT : Response code received is 404" >> $XCONF_LOG_FILE
            exit	
            # If a response code of 0 was received, the server is unreachable
            # Try reconnecting 
        elif [ $HTTP_RESPONSE_CODE -eq 0 ]; then            
            echo_t "XCONF SCRIPT : Response code 0, sleeping for 2 minutes and retrying" >> $XCONF_LOG_FILE
            # sleep for 2 minutes and retry
            sleep 120;

            retry_flag=1
            image_upg_avl=0

            #Increment the retry count
            xconf_retry_count=$((xconf_retry_count+1))

        fi

    done

    # If retry for 3 times done and image is not available, then exit
    # Cron scheduled job will be triggered later
    if [ $xconf_retry_count -eq 4 ] && [ $image_upg_avl -eq 0 ]
    then
        echo_t "XCONF SCRIPT : Retry limit to connect with XCONF server reached, so exit" 
        exit
    fi
}

calcRandTime()
{
    rand_hr=0
    rand_min=0
    rand_sec=0

    # Calculate random min
    rand_min=`awk -v min=0 -v max=59 -v seed="$(date +%N)" 'BEGIN{srand(seed);print int(min+rand()*(max-min+1))}'`

    # Calculate random second
    rand_sec=`awk -v min=0 -v max=59 -v seed="$(date +%N)" 'BEGIN{srand(seed);print int(min+rand()*(max-min+1))}'`

    #
    # Generate time to check for update
    #
    if [ $1 -eq '1' ]; then
        
        echo_t "XCONF SCRIPT : Check Update time being calculated within 24 hrs."
        echo_t "XCONF SCRIPT : Check Update time being calculated within 24 hrs." >> $XCONF_LOG_FILE

        # Calculate random hour
        # The max random time can be 23:59:59
        rand_hr=`awk -v min=0 -v max=23 -v seed="$(date +%N)" 'BEGIN{srand(seed);print int(min+rand()*(max-min+1))}'`

        echo_t "XCONF SCRIPT : Time Generated : $rand_hr hr $rand_min min $rand_sec sec"
        min_to_sleep=$(($rand_hr*60 + $rand_min))
        sec_to_sleep=$(($min_to_sleep*60 + $rand_sec))

        printf "XCONF SCRIPT : Checking update with XCONF server at \t";
        # date -d "$min_to_sleep minutes" +'%H:%M:%S'
        date -D '%s' -d "$(( `date +%s`+$sec_to_sleep ))"

        date_upgch_part="$(( `date +%s`+$sec_to_sleep ))"
        date_upgch_final=`date -D '%s' -d "$date_upgch_part"`

        echo_t "Checking update on $date_upgch_final" >> $XCONF_LOG_FILE

    fi

    #
    # Generate time to downlaod HTTP image
    # device reboot time 
    #
    if [ $2 -eq '1' ]; then
       
        if [ "$3" == "r" ]; then
            echo_t "XCONF SCRIPT : Device reboot time being calculated in maintenance window"
            echo_t "XCONF SCRIPT : Device reboot time being calculated in maintenance window" >> $XCONF_LOG_FILE
        fi 
                 
        # Calculate random hour
        # The max time random time can be 4:59:59
        rand_hr=`awk -v min=0 -v max=3 -v seed="$(date +%N)" 'BEGIN{srand(seed);print int(min+rand()*(max-min+1))}'`

        echo_t "XCONF SCRIPT : Time Generated : $rand_hr hr $rand_min min $rand_sec sec"

       if [ "$UTC_ENABLE" == "true" ]
	then
           cur_hr=`LTime H`
	   cur_min=`LTime M`
           cur_sec=`date +"%S"`
	else
           cur_hr=`date +"%H"`
           cur_min=`date +"%M"`
           cur_sec=`date +"%S"`
	fi

        # Time to maintenance window
        if [ $cur_hr -eq 0 ];then
            start_hr=0
        else
            start_hr=`expr 23 - ${cur_hr} + 1`
        fi

        start_min=`expr 59 - ${cur_min}`
        start_sec=`expr 59 - ${cur_sec}`

        # TIME TO START OF MAINTENANCE WINDOW
        echo_t "XCONF SCRIPT : Time to 1:00 AM : $start_hr hours, $start_min minutes and $start_sec seconds"
        min_wait=$((start_hr*60 + $start_min))
        # date -d "$time today + $min_wait minutes + $start_sec seconds" +'%H:%M:%S'
        date -D '%s' -d "$(( `date +%s`+$(($min_wait*60 + $start_sec)) ))"

        # TIME TO START OF HTTP_DL/REBOOT_DEV

        total_hr=$(($start_hr + $rand_hr))
        total_min=$(($start_min + $rand_min))
        total_sec=$(($start_sec + $rand_sec))

        min_to_sleep=$(($total_hr*60 + $total_min)) 
        sec_to_sleep=$(($min_to_sleep*60 + $total_sec))

        printf "XCONF SCRIPT : Action will be performed on ";
        # date -d "$sec_to_sleep seconds" +'%H:%M:%S'
        date -D '%s' -d "$(( `date +%s`+$sec_to_sleep ))"

        date_part="$(( `date +%s`+$sec_to_sleep ))"
        date_final=`date -D '%s' -d "$date_part"`

        echo_t "Action on $date_final" >> $XCONF_LOG_FILE
        touch $REBOOT_WAIT

    fi

    echo_t "XCONF SCRIPT : SLEEPING FOR $min_to_sleep minutes or $sec_to_sleep seconds"
    
    #echo "XCONF SCRIPT : SPIN 17 : sleeping for 30 sec, *******TEST BUILD***********"
    #sec_to_sleep=30

    sleep $sec_to_sleep
    echo_t "XCONF script : got up after $sec_to_sleep seconds"
}

# Get the MAC address of the WAN interface
getMacAddress()
{
	ifconfig  | grep $interface |  grep -v $interface:0 | tr -s ' ' | cut -d ' ' -f5
}

getBuildType()
{
   IMAGENAME=`cat /fss/gw/version.txt | grep imagename= | cut -d "=" -f 2`

   TEMPDEV=`echo $IMAGENAME | grep DEV`
   if [ "$TEMPDEV" != "" ]
   then
       type="DEV"
   fi

   TEMPVBN=`echo $IMAGENAME | grep VBN`
   if [ "$TEMPVBN" != "" ]
   then
       type="VBN"
   fi

   TEMPPROD=`echo $IMAGENAME | grep PROD`
   if [ "$TEMPPROD" != "" ]
   then
       type="PROD"
   fi

   TEMPCQA=`echo $IMAGENAME | grep CQA`
   if [ "$TEMPCQA" != "" ]
   then
       type="GSLB"
   fi
   
   echo_t "XCONF SCRIPT : image_type is $type"
   echo_t "XCONF SCRIPT : image_type is $type" >> $XCONF_LOG_FILE
}

 
removeLegacyResources()
{
	#moved Xconf logging to /var/tmp/xconf.txt.0
    if [ -f /etc/Xconf.log ]; then
		rm /etc/Xconf.log
    fi

	echo_t "XCONF SCRIPT : Done Cleanup"
	echo_t "XCONF SCRIPT : Done Cleanup" >> $XCONF_LOG_FILE
}

#####################################################Main Application#####################################################

# Determine the env type and url and write to /tmp/Xconf
#type=`printenv model | cut -d "=" -f2`

removeLegacyResources
getBuildType

# Check if the firmware download process is initiated by scheduler or during boot up.
triggeredFrom=""
if [ $1 -eq 1 ]
then
   echo_t "XCONF SCRIPT : Trigger is from boot" >> $XCONF_LOG_FILE
   triggeredFrom="boot"
elif [ $1 -eq 2 ]
then
   echo_t "XCONF SCRIPT : Trigger is from cron" >> $XCONF_LOG_FILE
   triggeredFrom="cron"
else
   echo_t "XCONF SCRIPT : Trigger is Unknown. Set it to boot" >> $XCONF_LOG_FILE
   triggeredFrom="boot"
fi

# If unit is waiting for reboot after image download,we need not have to download image again.
if [ -f $REBOOT_WAIT ]
then
    echo_t "XCONF SCRIPT : Waiting reboot after download, so exit" >> $XCONF_LOG_FILE
    exit
fi

if [ -f $DOWNLOAD_INPROGRESS ]
then
    echo_t "XCONF SCRIPT : Download is in progress, exit" >> $XCONF_LOG_FILE
    exit    
fi

echo_t "XCONF SCRIPT : MODEL IS $type" >> $XCONF_LOG_FILE

#Default xconf url
url="https://xconf.xcal.tv/xconf/swu/stb/"
 
# Override mechanism should work only for non-production build.
if [ "$type" != "PROD" ] && [ "$type" != "prod" ]; then
  if [ -f /nvram/swupdate.conf ]; then
      url=`grep -v '^[[:space:]]*#' /nvram/swupdate.conf`
      echo_t "XCONF SCRIPT : URL taken from /nvram/swupdate.conf override. URL=$url"
      echo_t "XCONF SCRIPT : URL taken from /nvram/swupdate.conf override. URL=$url"  >> $XCONF_LOG_FILE
  fi
fi

#s16 echo "$type=$url" > /tmp/Xconf
echo "URL=$url" > /tmp/Xconf
echo_t "XCONF SCRIPT : Values written to /tmp/Xconf are URL=$url"
echo_t "XCONF SCRIPT : Values written to /tmp/Xconf are URL=$url" >> $XCONF_LOG_FILE

# Check if the WAN interface has an ip address, if not , wait for it to receive one
estbIp=`ifconfig $interface | grep "inet addr" | tr -s " " | cut -d ":" -f2 | cut -d " " -f1`
estbIp6=`ifconfig $interface | grep "inet6 addr" | grep "Global" | tr -s " " | cut -d ":" -f2- | cut -d "/" -f1 | tr -d " "`

echo "[ $(date) ] XCONF SCRIPT - Check if the WAN interface has an ip address" >> $XCONF_LOG_FILE

while [ "$estbIp" = "" ] && [ "$estbIp6" = "" ]
do
    echo "[ $(date) ] XCONF SCRIPT - No IP yet! sleep(5)" >> $XCONF_LOG_FILE
    sleep 5

    estbIp=`ifconfig $interface | grep "inet addr" | tr -s " " | cut -d ":" -f2 | cut -d " " -f1`
    estbIp6=`ifconfig $interface | grep "inet6 addr" | grep "Global" | tr -s " " | cut -d ":" -f2- | cut -d "/" -f1 | tr -d " "`

    echo_t "XCONF SCRIPT : Sleeping for an ipv4 or an ipv6 address on the $interface interface "
done

echo_t "XCONF SCRIPT : $interface has an ipv4 address of $estbIp or an ipv6 address of $estbIp6"

    ######################
    # QUERY & DL MANAGER #
    ######################

# Check if new image is available
echo_t "XCONF SCRIPT : Checking image availability at boot up" >> $XCONF_LOG_FILE	
getFirmwareUpgDetail

if [ "$rebootImmediately" == "true" ];then
    echo_t "XCONF SCRIPT : Reboot Immediately : TRUE!!"
else
    echo_t "XCONF SCRIPT : Reboot Immediately : FALSE."

fi    

download_image_success=0
reboot_device_success=0
retry_download=0

while [ $download_image_success -eq 0 ]; 
do

    if [ ! -f $DOWNLOAD_INPROGRESS ]
    then
        touch $DOWNLOAD_INPROGRESS
    fi

    if [ $image_upg_avl -eq 1 ];then
       echo "$firmwareLocation" > /tmp/xconfdownloadurl

       # Set the url and filename
       echo_t "XCONF SCRIPT : URL --- $firmwareLocation and NAME --- $firmwareFilename" >> $XCONF_LOG_FILE
       $BIN_PATH/XconfHttpDl set_http_url $firmwareLocation $firmwareFilename
       set_url_stat=$?
        
       # If the URL was correctly set, initiate the download
       if [ $set_url_stat -eq 0 ];then
        
           # An upgrade is available and the URL has ben set 
           # Wait to download in the maintenance window if the RebootImmediately is FALSE
           # else download the image immediately

           if [ "$rebootImmediately" == "false" ];then
              echo_t "XCONF SCRIPT : Reboot Immediately : FALSE. Downloading image now" >> $XCONF_LOG_FILE
           else
              echo_t  "XCONF SCRIPT : Reboot Immediately : TRUE : Downloading image now" >> $XCONF_LOG_FILE
           fi
			
           # Start the image download
           echo "[ $(date) ] XCONF SCRIPT  ### httpdownload started ###" >> $XCONF_LOG_FILE
           $BIN_PATH/XconfHttpDl http_download
           http_dl_stat=$?
           echo "[ $(date) ] XCONF SCRIPT  ### httpdownload completed ###" >> $XCONF_LOG_FILE
           echo_t "**XCONF SCRIPT : HTTP DL STATUS $http_dl_stat**" >> $XCONF_LOG_FILE
			
           # If the http_dl_stat is 0, the download was succesful,          
           # Indicate a succesful download and continue to the reboot manager
		
           if [ $http_dl_stat -eq 0 ];then
               echo_t "XCONF SCRIPT : HTTP download Successful" >> $XCONF_LOG_FILE
               # Indicate succesful download
               download_image_success=1
               rm -rf $DOWNLOAD_INPROGRESS
           else
               echo_t "XCONF SCRIPT : HTTP download NOT Successful" >> $XCONF_LOG_FILE
               rm -rf $DOWNLOAD_INPROGRESS
               # No need of looping here as we will trigger a cron job at random time
               exit
           fi
       else
          retry_download=`expr $retry_download + 1`
          download_image_success=0
          if [ $retry_download -eq 3 ]
          then
             echo_t "XCONF SCRIPT : ERROR : URL & Filename not set correctly after 3 retries.Exiting" >> $XCONF_LOG_FILE
             rm -rf $DOWNLOAD_INPROGRESS
             exit  
          fi
       fi
    fi
done

    ##################
    # REBOOT MANAGER #
    ##################

    # Try rebooting the device if :
    # 1. Issue an immediate reboot if still within the maintenance window and phone is on hook
    # 2. If an immediate reboot is not possile ,calculate and remain within the reboot maintenance window
    # 3. The reboot ready status is OK within the maintenance window 
    # 4. The rebootImmediate flag is set to true

while [ $reboot_device_success -eq 0 ]; do
                    
    # Verify reboot criteria ONLY if rebootImmediately is FALSE
    if [ "$rebootImmediately" == "false" ];then

        # Check if still within reboot window



	if [ "$UTC_ENABLE" == "true" ]
	then
        	reb_hr=`LTime H`
	else
        	reb_hr=`date +"%H"`
	fi

        if [ $reb_hr -le 4 ] && [ $reb_hr -ge 1 ]; then
            echo_t "XCONF SCRIPT : Still within current maintenance window for reboot"
            echo_t "XCONF SCRIPT : Still within current maintenance window for reboot" >> $XCONF_LOG_FILE
            reboot_now=1    
        else
            echo_t "XCONF SCRIPT : Not within current maintenance window for reboot.Rebooting in  the next "
            echo_t "XCONF SCRIPT : Not within current maintenance window for reboot.Rebooting in  the next " >> $XCONF_LOG_FILE
            reboot_now=0
        fi

        # If we are not supposed to reboot now, calculate random time
        # to reboot in next maintenance window 
        if [ $reboot_now -eq 0 ];then
            calcRandTime 0 1 r
        fi    

        # Check the Reboot status
        # Continously check reboot status every 10 seconds  
        # till the end of the maintenace window until the reboot status is OK
        $BIN_PATH/XconfHttpDl http_reboot_status
        http_reboot_ready_stat=$?

        while [ $http_reboot_ready_stat -eq 1 ]   
        do     
            sleep 10

		if [ "$UTC_ENABLE" == "true" ]
		then
			cur_hr=`LTime H`
			cur_min=`LTime M`
		else
			 cur_hr=`date +"%H"`
			 cur_min=`date +"%M"`
		fi
            cur_sec=`date +"%S"`

            if [ $cur_hr -le 4 ] && [ $cur_min -le 59 ] && [ $cur_sec -le 59 ];
            then
                #We're still within the reboot window 
                $BIN_PATH/XconfHttpDl http_reboot_status
                http_reboot_ready_stat=$?
                    
            else
                #If we're out of the reboot window, exit while loop
                break
            fi
        done 

    else
        #RebootImmediately is TRUE
        echo_t "XCONF SCRIPT : Reboot Immediately : TRUE!, rebooting device now"
        http_reboot_ready_stat=0    
        echo_t "XCONF SCRIPT : http_reboot_ready_stat is $http_reboot_ready_stat"
                            
    fi 
                    
    echo_t "XCONF SCRIPT : http_reboot_ready_stat is $http_reboot_ready_stat" >> $XCONF_LOG_FILE

    # The reboot ready status changed to OK within the maintenance window,proceed
    if [ $http_reboot_ready_stat -eq 0 ];then
		        
        #Reboot the device
        echo_t "XCONF SCRIPT : Reboot possible. Issuing reboot command"
        echo_t "RDKB_REBOOT : Reboot command issued from XCONF"
        $BIN_PATH/XconfHttpDl http_reboot 
        reboot_device=$?
		       
        # This indicates we're within the maintenace window/rebootImmediate=TRUE
        # and the reboot ready status is OK, issue the reboot
        # command and check if it returned correctly
        if [ $reboot_device -eq 0 ];then
            reboot_device_success=1
            #For rdkb-4260
            echo_t "Creating file /nvram/reboot_due_to_sw_upgrade"
            touch /nvram/reboot_due_to_sw_upgrade
            echo_t "XCONF SCRIPT : REBOOTING DEVICE"
            echo_t "RDKB_REBOOT : Rebooting device due to software upgrade"
            echo_t "XCONF SCRIPT : setting LastRebootReason"
            dmcli eRT setv Device.DeviceInfo.X_RDKCENTRAL-COM_LastRebootReason string Software_upgrade
	    echo_t "XCONF SCRIPT : SET succeeded"
            
                
        else 
            # The reboot command failed, retry in the next maintenance window 
            reboot_device_success=0
            #Goto start of Reboot Manager again  
        fi

     # The reboot ready status didn't change to OK within the maintenance window 
     else
        reboot_device_success=0
        echo_t " XCONF SCRIPT : Device is not ready to reboot : Retrying in next reboot window ";
        # Goto start of Reboot Manager again  
     fi
                    
done # While loop for reboot manager
