#include <stdio.h>
#include <unistd.h>
#include <string.h>

#define RETRY_HTTP_DOWNLOAD_LIMIT 3
#define RETURN_OK 0

/*Typedefs Declared*/
typedef int INT;
typedef long LONG;

/*Global Definitions*/
int retry_limit=0;

int main(int argc,char *argv[])
{
    char pHttpUrl[200];
    char pfilename[200];
    LONG *pValue = NULL;
	int ret_code = 0;
    int http_status,reboot_status;
    int reset_device;

	if(strcmp(argv[1],"set_http_url") == 0)
    {
        if( ((argv[2]) != NULL) && ((argv[3]) != NULL) )
            {
                strcpy(pHttpUrl,argv[2]);
                strcpy(pfilename,argv[3]);
            	ret_code = Set_HTTP_Download_Url(pHttpUrl,pfilename);			
           	}
    }

	else if (strcmp(argv[1],"http_download")==0)
	{
	    http_status = HTTP_Download();

        //The return code is after RETRY_HTTP_DOWNLOAD_LIMIT has been reached 
        if(http_status == 200)
            ret_code = 0;
        
        else
            ret_code = 1;     
                          
	}

    else if (strcmp(argv[1],"http_reboot_status")==0)
	{

		reboot_status = Reboot_Ready(pValue);

        if(reboot_status == 1)
            ret_code = 0;
         
        else
            ret_code= 1;    
	}

    else if(strcmp(argv[1],"http_reboot")==0)
    {
		reset_device = HTTP_Download_Reboot_Now();
        
        if(reset_device == RETURN_OK)
            ret_code = 0;

        else
            ret_code= 1;
    }

    return ret_code;
}

INT Set_HTTP_Download_Url(char *pHttpUrl, char *pfilename)
{	
	int ret_stat = 0;

	/*Set the HTTP download URL*/
	ret_stat = cm_hal_Set_HTTP_Download_Url(pHttpUrl,pfilename);

	if(ret_stat == RETURN_OK)
	{

        /*Get the status of the set above*/
        ret_stat = cm_hal_Get_HTTP_Download_Url(pHttpUrl,pfilename);
		
		if(ret_stat == RETURN_OK)
			printf("\nXCONF BIN : URL has succesfully been set to --- %s\n",pHttpUrl);
		else
			printf("\nXCONF BIN : HTTP url GET error");
	}
	
	else
    {
	    printf("\nXCONF BIN : HTTP url SET error"); 			
    }

    return ret_stat ;
}

INT HTTP_Download ()
{   
    int ret_stat;
    int http_dl_status=0;
    int retry_http_status=1;
    int retry_http_dl=1;

    while((retry_limit < RETRY_HTTP_DOWNLOAD_LIMIT) && (retry_http_dl==1))
    {
            ret_stat = cm_hal_HTTP_Download ();

            /*If the HTTP download started succesfully*/
            if(ret_stat == RETURN_OK)
            {
                printf("\nXCONF BIN : HTTP download started\n");
                /*
                 * Continue to get the download status if the retry_http_status flag is set,
                 * implying the image is being downloaded and disable the retry_http_dl flag.
                 *
                 * Stop getting the image download status, if the download was succesfull or
                 * if an error was received, in which case retry the http download
                 */
                
                /*
                 * Sleeping since the status returned is 
                 * 500 on immediate status query
                 */
                sleep(1);

                while(retry_http_status ==1)
                {    
                    /*Get the download status till SUCCESS*/
                    http_dl_status = cm_hal_Get_HTTP_Download_Status();
            
                    /*Download completed succesfully*/
                    if(http_dl_status ==200)
                    {
                        printf("\nXCONF BIN : HTTP download COMPLETED with status : %d\n",http_dl_status);
                        retry_http_status=0;
                        retry_http_dl=0;

                        //printf("\nBIN : retry_http_status : %d",retry_http_status);
                        //printf("\nBIN : retry_dl_status : %d",retry_http_dl);

                    }
                    
                    else if (http_dl_status == 0)
                    {

                        printf("\nXCONF BIN : HTTP download is waiting to start with status : %d",http_dl_status);
                        
                        retry_http_dl=0;    
                        
                        sleep(5);
                        
                    }        
                    else if((http_dl_status>0)&&(http_dl_status<=100))
                    {   
                        //This is already set to 1
                        //retry_http_status=1;
                        retry_http_dl=0;

                        printf("\nXCONF BIN : HTTP download in PROGRESS with status :  %d%%",http_dl_status);
                        
                        sleep(2);
                    }
                

                    /* If an error is received, set the retry_http_dl flag
                     * and retry the download
                     */
                    else if (http_dl_status > 400)
                    {
                        printf("\nXCONF BIN : HTTP download ERROR with status : %d. Exiting.",http_dl_status);
                        retry_http_dl=0;
                        retry_http_status=0;
                        
                    }
                            
                }
                          
            }//If condition

            /* If the HTTP download status returned with an error, 
             * a download was already in progress, 
             * retry after sleep
             */
            else
            {
                printf("\nXCONF BIN : HTTP Download not started. Retrying download after some time"); 

                /*This is to indicate that the actual download never started
                since a secondary download never ended or there was an error*/
                
                http_dl_status =-1;

                retry_http_dl=1;
                retry_limit++;
                sleep(10);
            }

    }//While condition 

    /*
     * The return status can either be
     * 200  : The download was succesful
     * >400 : An error was encountered even after RETRY_HTTP_DOWNLOAD_LIMIT retries
     * -1   : The actual http dl never started due to a secondary dl in progress or the primary dl not starting
     */
    return http_dl_status;  
    
}
	

INT Reboot_Ready(LONG *pValue)
{
    //cm_hal_Reboot_Ready(pValue);
    return RETURN_OK;    
}

INT HTTP_Download_Reboot_Now ()
{
int http_reboot_stat; 

http_reboot_stat= cm_hal_HTTP_Download_Reboot_Now();

if(http_reboot_stat == RETURN_OK)
    printf("\nXCONF BIN : Rebooting the device now!\n");

else
    printf("\nXCONF BIN : Reboot in progress. ERROR!\n");

return  http_reboot_stat;       
}
