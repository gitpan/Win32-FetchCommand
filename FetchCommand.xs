#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

static DWORD ext_search (const char *type, const char *szName, const char *ext, char *szExecutable)
{
   /* Would be nicer to use the Shell API FindExecutable,
      but that's not always available, so we write our own */

   DWORD dwResult;
   HKEY	hExt, hCmd;
   DWORD dwlen;
   char RegValue[FILENAME_MAX+1];

   dwResult = RegOpenKeyEx(HKEY_CLASSES_ROOT, ext, 0, KEY_READ, &hExt);	
   if ( dwResult != ERROR_SUCCESS)
      return dwResult;
   
   dwlen = FILENAME_MAX;
	dwResult = RegQueryValueEx(hExt, NULL, NULL, NULL, (LPBYTE)&RegValue, &dwlen);
   if ( dwResult != ERROR_SUCCESS)
      return dwResult;

   RegCloseKey(hExt);

   /* strcat (RegValue, "\\shell\\open\\command"); */
   sprintf (RegValue, "%s\\shell\\%s\\command", RegValue, type);

   dwResult = RegOpenKeyEx(HKEY_CLASSES_ROOT, RegValue, 0, KEY_READ, &hCmd);	
   if ( dwResult != ERROR_SUCCESS)
      return dwResult;

   dwlen = FILENAME_MAX;
	dwResult = RegQueryValueEx(hCmd, NULL, NULL, NULL, (LPBYTE)&RegValue, &dwlen);
   if ( dwResult != ERROR_SUCCESS)
      return dwResult;

   RegCloseKey (hCmd);

   strcpy (szExecutable, RegValue);
   
   return ERROR_SUCCESS;      

} 


MODULE = Win32::FetchCommand		PACKAGE = Win32::FetchCommand			


SV *
FetchCommand(szName, ...)
   const char *szName;

   PROTOTYPE: $;$

   CODE:
      DWORD dwRetn;
      char szCmd[FILENAME_MAX+1];
      int iArgs = 0;
      char *astr = szCmd;
      BOOL bNameInserted = FALSE;
      const char *type;
      int i;
      const char *ext = strrchr(szName, '.');

      if (!ext)
         XSRETURN_EMPTY;

      if ( items > 1 )
      {
         STRLEN n_a;
         type = (char *)SvPV(ST(1), n_a);
      }
      else
         type = "open";

      dwRetn = ext_search (type, szName, ext, szCmd);
      if ( dwRetn != ERROR_SUCCESS)
      {
         SetLastError(dwRetn);    /* Registry APIs don't do this */
                                  /* Ensure $^E is updated       */
         XSRETURN_EMPTY;          /* Return nothing */
      }

      /* Loose the arguments on the stack */
      for ( i = 0; i < items; i++)
         POPs;  

      /* fprintf (stderr, "\nFor extension %s found <%s>\n", ext, szCmd); */
         
      /* I would prefer to use strtok, BUT...                     */
      /* Some commands are quoted (Imbedded spaces in file names) */
      /* Some commands are not quoted                             */
      /* Some commands have both quoted and non-quoted strings!   */
         
      for (iArgs = 0; astr && *astr; iArgs++ )
      {
         char delim;
         char *tokend;
         char *percent;
         int iLen;

         if (*astr == '"')
            delim = '"';
         else
            delim = ' ';

         /* fprintf (stderr, "delim: <%c>, astr: %s\n", delim, astr); */
         if (*astr == delim)
            astr++;

         tokend = strchr (astr, delim);
         if (tokend) 
            *tokend = '\0';   
            
         iLen = strlen(astr);

         /* It would be nice to be more sophisticated here,            */
         /* with other command line arguments, but this is all we have */

         /* Environment variable or insertion string? */
         percent = strchr (astr, '%');
         
         if ( percent )
         {
            char *bstr = percent + 1;

            /* Check for %1, %l (lower 'ell'), %L, %* */
            if (*bstr == '1' || *bstr == 'l' || *bstr == 'L' || *bstr == '*')
            { 
               if (!bNameInserted && *bstr != '*')
               {
                  char szWk[FILENAME_MAX+1] = {0};
                  int wkLen = percent - astr;
                  BOOL bQuoted = FALSE;

                  if ( percent > astr && *(percent - 1) == '\"')
                  {
                    wkLen--;
                    bQuoted = TRUE;
                  }
  
                  strncpy (szWk, astr, wkLen);
                  strcat (szWk, szName);
                  bstr++;

                  if (bQuoted && *bstr == '\"')
                     bstr++;

                  strcat (szWk, bstr);
                  XPUSHs(sv_2mortal(newSVpvn (szWk, strlen(szWk))));
  
                  /* XPUSHs(sv_2mortal(newSVpvn (szName, strlen(szName)))); */
                  bNameInserted = TRUE;
               }
               else if ( *bstr == '*' )
               {
                  /* Ignore it */
                  iArgs--;
               }
               else
               {                  
                  XPUSHs(sv_2mortal(newSVpvn (astr, iLen))); 
               }
            }   
            else
            {
               /* Environment variable? */
               
               char szWk[FILENAME_MAX+1] = {0};
               char szFullPath[FILENAME_MAX+1] = {0};

               strncpy (szWk, astr, iLen);

               ExpandEnvironmentStrings(szWk, szFullPath, FILENAME_MAX+1);

               XPUSHs(sv_2mortal(newSVpvn (szFullPath, strlen(szFullPath))));
            }
         }
         else
         {
            /* Not an insertion string or env. var. */
            XPUSHs(sv_2mortal(newSVpvn (astr, iLen)));
         }

         astr = tokend;

         if (astr)
         {
            astr++;

            /* Tokens ending in " are still space delimited */
            if (delim == '"' && *astr == ' ')
               astr++;
         }
      }

      if ( !bNameInserted )
      {
         /* At this point we did not encounter an insersion string, so add the filename */

         XPUSHs(sv_2mortal(newSVpvn (szName, strlen(szName))));
         iArgs++;
      }

      XSRETURN(iArgs);
                     

   OUTPUT:
      RETVAL

