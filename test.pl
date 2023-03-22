use strict;
use Date::Manip;
use MIME::Lite;
use Time::HiRes qw(gettimeofday);
use Net::FTP;
use Net::Ping;
use File::Path;
use File::Find;
use File::Copy;
use DBI;
use Getopt::Long;
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use lib "$ENV{BNR_SCH_ROOT}/BNR-SCH/NRIPRD1/NRIPRD1_Manual_HTML_Preprocessing"; use TRWFileTransferConfig;
use File::Basename;
use lib "$ENV{BNR_SCH_ROOT}/BNR-SCH/Config";
use MAILHTMLCONFIG;
use Sys::Hostname;
#-------------------------------------------------
# production - config
#-------------------------------------------------
#my $sMailingList = qq {From: Data Production <DataProduction\@NewRiver.com> #To: Data Production Alert <DataProdAlert\@NewRiver.com>};
my ($sFrom,$sTo,$sCc,$sSubject,$sMail,$slast_run_date); my $FailCounter=1;
my $sErrorFrom = $MAILHTMLCONFIG::ErrorFrom;
my $sErrorTo = $MAILHTMLCONFIG::Errorto;
my $sErrorCc = 'DELHFilingsPreprocessing@broadridge.com'; #my $sErrorTo = 'omprakash.singh@broadridge.com';
#my $sErrorCc = 'satyabrata.satpathy@broadridge.com'; $sFrom = $MAILHTMLCONFIG::From;
my $sPickupDir = 'C:/Inetpub/Mailroot/Pickup'; # Mail Pickup Directory my $sSMTPServer = $MAILHTMLCONFIG::SMTPServer;
my $sPNetDir = $PETRWFTPCONFIG::kStrDirPNet; # PNet Filings Directories
my $sFilesToUploadDir; my $sLocalFtpInDir;
my $sLocalFtpOutDir;
 my $sLocalExtractDir;
my $sHTMLErrorFilesDir;
my $sHTMLAutoValidatorInDir; my $sLogDir;
my $sFtpDir;
my $sFlagFileSuffix_SanDirCopyDone = ".flag.done.copy.sandir"; my $sFlagFileSuffix_SanTxtCopyDone = ".flag.done.copy.santxt"; my $logfile;
my $ftp;
## FTP info
#my $sFTPURL = 'ftp.test.com'; #my $sFTPUser = ' ';
#my $sFTPPassword = ' ';
###### New FTP username and pwd #######
my $sFTPURL = 'nrftpprod.broadridge.net'; my $sFTPUser = 'ADP-ICD\sa-nrftpprod'; my $sFTPPassword = '@Wsxedc90';
#######################################
my $dbh = DBI->connect("dbi:Oracle:$ENV{BNR_DB_PNET}", "$ENV{BNR_PNET_DP_USER}", "$ENV{BNR_PNET_DP_USER_PWD}", { RaiseError => 1 , AutoCommit => 0});
#-------------------------------------------------
# test - config
#-------------------------------------------------
# my $sMailingList = qq {From: Data Production <DataProduction\@NewRiver.com> # To: Data Production Alert <Amit Bhardwaj\@NewRiver.com>};
my $sPNetDir = 'E:/PNetFilings/SEC/Filings'; # PNet Filings Directories #my $sPNetDir = 'I:/SEC/Filings'; # PNet Filings Directories
my $sProcessOption;
sub main() {
GetOptions("task=s", \$sProcessOption);

 if (uc $sProcessOption eq 'UPLOADHTMLERRORFILINGS') {
$sLogDir = "$PETRWFTPCONFIG::kStrDirLog/HTMLCorrection"; $sFilesToUploadDir = $PETRWFTPCONFIG::kStrDirHTMLError; $sLocalFtpOutDir =
"$PETRWFTPCONFIG::kStrDirHTMLFtpOut/HTMLCorrection"; $sFtpDir = $PETRWFTPCONFIG::kStrDirHTMLFtp;
} elsif (uc $sProcessOption eq 'UPLOADASCIIERRORFILINGS') { $sLogDir = "$PETRWFTPCONFIG::kStrDirLog/ASCIICorrection"; $sFilesToUploadDir = $PETRWFTPCONFIG::kStrDirASCIIError; $sLocalFtpOutDir =
"$PETRWFTPCONFIG::kStrDirASCIIFtpOut/ASCIICorrection"; $sFtpDir = $PETRWFTPCONFIG::kStrDirASCIIFtp;
}elsif (uc $sProcessOption eq 'UPLOADPNETFILINGS') {
$sLogDir = "$PETRWFTPCONFIG::kStrDirLog/PNETProcessing"; $sFilesToUploadDir = $PETRWFTPCONFIG::kStrDirPNetConverted; $sLocalFtpOutDir = $PETRWFTPCONFIG::kStrDirPNetFtpOut; $sFtpDir = $PETRWFTPCONFIG::kStrDirPNetFtp;
} elsif (uc $sProcessOption eq 'EXTRACTCORRECTEDHTMLFILINGS') {
$sLogDir = "$PETRWFTPCONFIG::kStrDirLog/HTMLExtract";
$sLocalFtpInDir = $PETRWFTPCONFIG::kStrDirCorrectedHTMLFtpIn; $sLocalExtractDir = $PETRWFTPCONFIG::kStrDirCorrectedHTMLExtract; $sHTMLAutoValidatorInDir = $PETRWFTPCONFIG::kStrDirHTMLAutoValidator; $sHTMLErrorFilesDir = $PETRWFTPCONFIG::kStrDirHTMLError;
} else {
print STDOUT "Unknown option: $sProcessOption\n";
print STDOUT "Please use 'HTML' for sending files for correction and 'PNET' for
PNet processing\n"; return;
}
$sSubject= "TRW File Transfer ($sProcessOption)";
if (! -d $sLogDir) { mkpath $sLogDir or die "Cannot create $sLogDir"; }
my ($sec, $min, $hr, $mday, $mon, $yr, $wday, $yda, $isdst) = localtime; $logfile = sprintf("$sLogDir/%04d%02d%02d.log", $yr+1900, $mon+1, $mday);
writeLogln("Started TRW File Transfer ($sProcessOption) by ".getlogin."."); my ($sec, $min, $hr, $mday, $mon, $yr, $wday, $yda, $isdst) = localtime;
if (uc $sProcessOption eq 'UPLOADHTMLERRORFILINGS') {
if (! -d $sLocalFtpOutDir) { mkpath $sLocalFtpOutDir or die "Cannot create
$sLocalFtpOutDir"; } #

 # Prepare files for Copy/FTP Upload.
#
prepareFiles($sFilesToUploadDir,$sLocalFtpOutDir, '');
#
# Upload files which has flag a file
#
$ftp = loginToFTP(); uploadFiles($sLocalFtpOutDir, $sFtpDir) if $ftp; $ftp->quit;
$dbh->disconnect;
} elsif (uc $sProcessOption eq 'UPLOADASCIIERRORFILINGS') {
if (! -d $sLocalFtpOutDir) { mkpath $sLocalFtpOutDir or die "Cannot create
$sLocalFtpOutDir"; } #
# Prepare files for Copy/FTP Upload.
#
prepareFiles($sFilesToUploadDir,$sLocalFtpOutDir, '');
#
# Upload files which has flag a file
#
$ftp = loginToFTP(); uploadFiles($sLocalFtpOutDir, $sFtpDir) if $ftp; $ftp->quit;
$dbh->disconnect;
} elsif (uc $sProcessOption eq 'UPLOADPNETFILINGS') {
if (! -d $sLocalFtpOutDir) { mkpath $sLocalFtpOutDir or die "Cannot create
$sLocalFtpOutDir"; } #
# Prepare files for Copy/FTP Upload.
#
prepareFiles($sFilesToUploadDir,$sLocalFtpOutDir, '');
# To handle PNET processsing files foreach my $dir ($sPNetDir)
{
# All destination directories
my $sDstDir = $dir; copyFiles($sLocalFtpOutDir, $sDstDir, '');
} updatePNetFilingSizes();
#

 # Upload files which has flag a file
#
$ftp = loginToFTP(); uploadFiles($sLocalFtpOutDir, $sFtpDir) if $ftp; $ftp->quit;
} elsif (uc $sProcessOption eq 'EXTRACTCORRECTEDHTMLFILINGS') {
if (! -d $sLocalExtractDir) { mkpath $sLocalExtractDir or die "Cannot create $sLocalExtractDir"; }
#
# Upload files which has flag a file
# moveAndExtractFiles($sLocalFtpInDir,$sLocalExtractDir);
#
# Re-process the manual corrected files using Automated Validator
#
copyToAutomatedValidator($sLocalExtractDir, $sHTMLAutoValidatorInDir);
} else {
print STDOUT "Unknown option: $sProcessOption\n";
print STDOUT "Please use 'HTML' for sending files for correction and 'PNET' for
PNet processing\n"; }
writeLogln("Completed processing TRW File Transfer."); }
# Prepare the files for FTP sub prepareFiles($$$)
{
# #
my ($sInDir, $sFtpOutDir, $sDir) = @_; my (@files, $sFile, $sFlagFilePath);
if (! opendir FILES, $sInDir) {
writeLogln("Access to Share $sInDir failed Sleeping 10s.."); sleep(10);
writeLogln("Access to Share $sInDir Trying..");
opendir FILES, $sInDir or die $!."\n(".$sInDir.")\t";
print ("Status is $sInDir\n");
}
opendir FILES, $sInDir or die $!."\n(".$sInDir.")\t";

 @files = readdir FILES; closedir FILES;
for $sFile(@files)
{
next if $sFile=~/^\.*$/;
next if $sFile=~/^Bak$/i;
# dont copy the san dir copy done flag file
next if $sFile=~/$sFlagFileSuffix_SanDirCopyDone/i;
next if $sFile!~/^\d{10}-\d{2}-\d{6}\.txt$/; my $sSrcFile = "$sInDir/$sFile";
writeLogln("Copying $sSrcFile (".(-s $sSrcFile).")"); if (-d $sSrcFile)
{
# Image Directory
# if SanDir flag file exists copy SanDir files
$sFlagFilePath = $sInDir . "\\" . $sFile . $sFlagFileSuffix_SanDirCopyDone; if (-e $sFlagFilePath)
{
# copy SanDir files to destination dir(s) prepareFiles($sSrcFile, $sFtpOutDir, $sFile); # remove SanDir from source dir
if (rmdir $sSrcFile)
{
writeLogln("Removed directory $sSrcFile."); }
else {
writeLogln("Error removing directory $sSrcFile: $!"); }
# remove the sandir flag file if (unlink($sFlagFilePath))
{
writeLogln("Removed SanDir FlagFile $sFlagFilePath."); }
else {
die("Error Removing SanDir FlagFile sFlagFilePath: $!."); }
# create sanddir copy done flag file
$sFlagFilePath = $sFtpOutDir . "\\" . $sFile . $sFlagFileSuffix_SanDirCopyDone;
open FLAG_FILE, ">>$sFlagFilePath" or die "Create File Failed - $sFlagFilePath - $!"; print FLAG_FILE "done";
close FLAG_FILE;
writeLogln("Created SanDir FlagFile $sFlagFilePath.");
}

 }
else
{ # Filings
# All destination directories
prepareFile($sInDir, $sFile, $sFtpOutDir, $sDir); writeLogln("Copied to $sFtpOutDir.");
} }
}
sub prepareFile($$$$) {
my ($sSrcDir, $sFile, $sFtpOutDir, $sDir) = @_; my ($sFlagFilePath);
# Filings
# All destination directories
my $sDstDir = $sFtpOutDir; $sDstDir .= "/$sDir" if $sDir;
my $sSrcFile = "$sSrcDir/$sFile"; if (! -d $sDstDir)
{
mkpath $sDstDir or die "Error creating $sDstDir: $!"; }
copy($sSrcFile, $sDstDir) or die "Error copying to $sDstDir: $!"; if (!unlink($sSrcFile))
{
die("Error removing $sSrcFile: $!."); }
# create the santxt copy done flag file if ($sFile =~ /.txt/gi)
{
$sFlagFilePath = $sFtpOutDir . "\\" . $sFile;
$sFlagFilePath =~ s/.txt/$sFlagFileSuffix_SanTxtCopyDone/gi;
open FLAG_FILE, ">>$sFlagFilePath" or die "Create File Failed - $sFlagFilePath - $!"; print FLAG_FILE "done";
close FLAG_FILE;
} }
sub copyFiles() {
my ($sInDir, $sDstDir, $sDir) = @_; my (@files, $sFile, $sFlagFilePath); opendir FILES, $sInDir or die $!;

 @files = readdir FILES; closedir FILES;
for $sFile(@files)
{
next if $sFile =~ /^\.*$/;
next if $sFile =~ /$sFlagFileSuffix_SanDirCopyDone/gi; next if $sFile =~ /$sFlagFileSuffix_SanTxtCopyDone/gi;
my $sSrcFile = "$sInDir/$sFile"; my $sDstFile = "$sDstDir/$sFile";
if (-d $sSrcFile) { # Directory
my $sFlagFilePathSrc = "$sSrcFile$sFlagFileSuffix_SanDirCopyDone";
} else {
next if -e !$sFlagFilePathSrc;
my $sDstDir = "$sDstDir/$sFile"; copyFiles($sSrcFile,$sDstDir,$sFile);
if ($sDir) {
if (! -d $sDstDir)
{
mkpath $sDstDir or die "Error creating $sDstDir: $!"; writeLogln("Created directory $sDstDir.");
} } else {
my $sFlagFilePathSrc = $sSrcFile;
$sFlagFilePathSrc =~ s/.txt/$sFlagFileSuffix_SanTxtCopyDone/gi; next if -e !$sFlagFilePathSrc;
}
copy($sSrcFile, $sDstFile) or die "Error copying to $sDstDir: $!"; writeLogln("Copied to $sDstFile.");
} }
}
sub uploadFiles($$) {
my ( $sLocalDir, $sFtpDir ) = @_;
my (@files, $sFile, $sFlagFilePathSrc, $sFlagFilePathDst); writeLogln("Scanning $sLocalDir ...");
opendir FILES, $sLocalDir or die $!;
@files = readdir FILES;
closedir FILES;
# Write no. of filings
writeLogln( "No. of filings to upload: " . ( scalar(@files) - 2 ) );

 for $sFile (@files) {
next if $sFile =~ /^\.*$/;
# dont ftp the flag files
next if $sFile =~ /$sFlagFileSuffix_SanDirCopyDone/gi; next if $sFile =~ /$sFlagFileSuffix_SanTxtCopyDone/gi;
next if $sFile =~ /\.ZIP$/gi; my $sSrcFile = "$sLocalDir/$sFile"; my $sDstFile = "$sFtpDir/$sFile";
my $sSAN = ();
$sSAN = $sFile;
$sSAN =~ s/\.txt//;
my $sSANsize = ();
$sSANsize = (stat("$sSrcFile"))[7];
my $sSANlastmodtime = ();
$sSANlastmodtime = (stat("$sSrcFile"))[9];
my ($sec, $min, $hr, $mday, $mon, $yr, $wday, $yda, $isdst) = (); ($sec, $min, $hr, $mday, $mon, $yr, $wday, $yda, $isdst) =
localtime($sSANlastmodtime);
my $sSANlastmodtime = sprintf("%02d-%02d-%04d %02d:%02d:%02d",
$mon+1, $mday, $yr+1900, $hr, $min, $sec);
my $sSANlmodtime = sprintf("%02d%02d%04d%02d%02d%02d", $mon+1,
$mday, $yr+1900, $hr, $min, $sec);
$sDstFile =~ s/^\/*(.*)$/$1/; # set flag paths
if ( -d $sSrcFile ) {
$sFlagFilePathSrc = "$sSrcFile$sFlagFileSuffix_SanDirCopyDone"; $sFlagFilePathDst = "$sDstFile$sFlagFileSuffix_SanDirCopyDone";
} else {
$sFlagFilePathSrc = $sSrcFile;
$sFlagFilePathSrc =~ s/.txt/$sFlagFileSuffix_SanTxtCopyDone/gi; $sFlagFilePathDst = $sDstFile;
$sFlagFilePathDst =~ s/.txt/$sFlagFileSuffix_SanTxtCopyDone/gi;
}
# zip sandir
if ( -d $sSrcFile && -e $sFlagFilePathSrc ) {
# zip SanDir\* in ftp dir as ftpdir\San_dir.zip #writeLogln("Zipping $sSrcFile");
writeLogln("Zipping $sFile");
my $oZipper = Archive::Zip->new();
$oZipper->addTree( $sSrcFile , $sFile);
$sSrcFile = $sSrcFile . "_dir.zip";
$sDstFile = $sDstFile . "_dir.zip";
my $nRetCode = $oZipper->writeToFileNamed($sSrcFile);

 if ( $nRetCode != AZ_OK ) {
die("Create Zip Failed - $sSrcFile - nRetCode = $nRetCode");
} else {
#writeLogln("Create Zip Passed - $sSrcFile"); writeLogln("Create Zip Passed - $sFile");
}
$oZipper = undef; }
# zip santxt
if ( $sSrcFile =~ /.txt/gi && -e $sFlagFilePathSrc ) {
# zip San.txt as San.zip
# writeLogln("Zipping $sSrcFile");
writeLogln("Zipping $sFile");
my $oZipper = Archive::Zip->new();
$oZipper->addFile( $sSrcFile, $sFile );
$sSrcFile =~ s/.txt/.zip/gi;
$sDstFile =~ s/.txt/.zip/gi;
my $nRetCode = $oZipper->writeToFileNamed($sSrcFile); if ( $nRetCode != AZ_OK ) {
die("Create Zip Failed - $sSrcFile - nRetCode = $nRetCode"); } else {
#writeLogln("Create Zip Passed - $sSrcFile");
writeLogln("Create Zip Passed - $sFile"); }
$oZipper = undef; }
my ($zipftpmsg,$zipftpcode,$flagftpmsg,$flagftpcode); # ftp zip + ftp flag file + delete all source files
if ( $sSrcFile =~ /.zip/gi ) {
my $selectsql =qq/select NVL(count(t.sec_access_num),0) from pod_sys.T_MANUL_SAN_PREPRC t
where t.isuploadreq=1 and t.status=4 and t.sec_access_num='$sSAN'/;
my $rowexist = &getDBRows($dbh, $selectsql); my $nExist = $rowexist->[0]->[0];
if($nExist > 0)
{
# Database Entry
if (uc $sProcessOption eq 'UPLOADHTMLERRORFILINGS') {
my $sql = qq/ BEGIN P_MANUL_SAN_PREPRC(p_san=>
'$sSAN',p_loadtype=>'U',p_timestamp=> sysdate, p_filesize=> $sSANsize, p_lastmodtime=> to_date('$sSANlastmodtime','MM-DD-YYYY HH24:MI:SS'),p_uploadtype=>'HTML');
END;

 if ($DBI::err) {
if ($DBI::err) {
/;
my $sth = $dbh->prepare($sql);
writeLogln($DBI::errstr);
die "Database Entry prepare Failed for san: '$sSAN'\n";
} eval{
}; if($@)
writeLog("Executing Main SQL \n");
$sth->execute; $sth->finish();
{
writeLog("Database Entry Fail: $@\n");
die "Database Entry Failed for san: '$sSAN'\n";
}
} elsif (uc $sProcessOption eq 'UPLOADASCIIERRORFILINGS') {
my $sql = qq/ BEGIN P_MANUL_SAN_PREPRC(p_san=>
'$sSAN',p_loadtype=>'U',p_timestamp=> sysdate, p_filesize=> $sSANsize, p_lastmodtime=> to_date('$sSANlastmodtime','MM-DD-YYYY HH24:MI:SS'),p_uploadtype=>'ASCII');
END; /;
my $sth = $dbh->prepare($sql);
writeLogln($DBI::errstr);
die "Database Entry prepare Failed for san: '$sSAN'\n";
} eval{
}; if($@) {
writeLog("Executing Main SQL \n");
$sth->execute; $sth->finish();
writeLog("Database Entry Fail: $@\n");
die "Database Entry Failed for san: '$sSAN'\n"; }
}

 #to be removed for prod release #$ftp->quit;
# ftp zip
my $localsizeZip = -s $sSrcFile;
my $sizeZip = $ftp->size($sDstFile); #if ( $sizeZip != $localsizeZip ) {
writeLogln("Uploading $localsizeZip bytes to $sDstFile ($sizeZip)... "); if ($ftp->put( $sSrcFile, $sDstFile ))
{ writeLogln("Uploaded complete");
#$sizeZip = $ftp->size($sDstFile); }
else
{ RollBack($sSAN,$sSANsize,$sSANlastmodtime);
die("Error with upload for SAN $sSAN: $!"); }
writeLogln("Zip Ftp:\n".$ftp->message()); $zipftpmsg=$ftp->message(); $zipftpcode=$ftp->code();
#} #else{
# writeLogln("Zip Ftp: By Passing");
# $zipftpmsg="Transfer complete"; # $zipftpcode=226;
#}
# ftp flag file
my $localsizeFlag = -s $sFlagFilePathSrc;
my $sizeFlag = $ftp->size($sFlagFilePathDst);
#if ( $sizeFlag != $localsizeFlag ) {
writeLogln("Uploading $localsizeFlag bytes to $sFlagFilePathDst ($sizeFlag)... "); if ($ftp->put( $sFlagFilePathSrc, $sFlagFilePathDst ))
{ writeLogln("Uploaded complete");
#$sizeFlag = $ftp->size($sFlagFilePathDst); }
else
{ RollBack($sSAN,$sSANsize,$sSANlastmodtime);
die("Error with upload of SAN Flag file $sSAN: $!");

 } writeLogln("Flag Ftp:\n".$ftp->message());
$flagftpmsg=$ftp->message();
$flagftpcode=$ftp->code(); #}
#else{
#writeLogln("Flag Ftp: By Passing");
#$flagftpmsg="Transfer complete"; #$flagftpcode=226;
#}
# if ftp worked
#if ( $sizeZip == $localsizeZip && $sizeFlag == $localsizeFlag ) {
if ($zipftpmsg =~ /Transfer complete/ && $zipftpcode eq 226 && $flagftpmsg =~
/Transfer complete/ && $flagftpcode eq 226) {
# delete zip file
my $nRet = unlink($sSrcFile); if ( $nRet == 1 ) {
#writeLogln("Removed Zip $sSrcFile.");
writeLogln("Removed Zip $sFile."); } else {
die("Error Removing Zip $sSrcFile: $!"); }
# if SanDir
if ( index($sSrcFile,"_dir.zip") > -1 ) {
$sSrcFile =~ s/_dir.zip//gi; # delete SanDir\*
if (rmtree($sSrcFile)) {
#writeLogln("Removed SanDir - $sSrcFile.");
writeLogln("Removed SanDir - $sFile."); } else {
die("Error removing SanDir - $sSrcFile: $!"); }
# if SanTxt } else {
# delete San.txt $sSrcFile =~ s/.zip/.txt/gi;
'UPLOADHTMLERRORFILINGS') {
if (uc $sProcessOption eq
copy($sSrcFile, "$PETRWFTPCONFIG::kStrDirHTMLErrorBKP/$sSANlmodtime"."_".
uc(sprintf("%02d%s%04d%02d%02d%02d",(split(/[ ,:]/,localtime))[2,1,6,3,4,5])) ."_" . basename $sSrcFile);

 'UPLOADASCIIERRORFILINGS') {
} elsif (uc $sProcessOption eq
copy($sSrcFile, "$PETRWFTPCONFIG::kStrDirASCIIErrorBKP/$sSANlmodtime"."_".
uc(sprintf("%02d%s%04d%02d%02d%02d",(split(/[ ,:]/,localtime))[2,1,6,3,4,5])) ."_" . basename $sSrcFile);
}
if (unlink("$sSrcFile")) { #writeLogln("Removed SanTxt - $sSrcFile."); writeLogln("Removed SanTxt - $sFile.");
} else {
die("Error Removing SanTxt - $sSrcFile: $!.");
} }
# delete flagfile
if (unlink($sFlagFilePathSrc)) {
writeLogln("Removed FlagFile - ". basename $sFlagFilePathSrc); } else {
die("Error Removing FlagFile - $sFlagFilePathSrc: $!."); }
# if ftp failed } else {
#my $sErrMsg = "Failed to upload Zip: $sSrcFile -- sizes don't match ($localsizeZip/$sizeZip).\n";
#$sErrMsg .= "or failed to upload Flag: $sFlagFilePathSrc -- sizes don't match ($localsizeFlag/$sizeFlag).";
\n";
my $sErrMsg = "Failed to upload Zip: $sSrcFile -- $zipftpcode : $zipftpmsg. \n"; $sErrMsg .= "or failed to upload Flag: $sFlagFilePathSrc -- $flagftpcode : $flagftpmsg.
writeLogln($sErrMsg); RollBack($sSAN,$sSANsize,$sSANlastmodtime);
# Deleting Zip file after fail to upload
my $nRet = unlink($sSrcFile);
if ( $nRet == 1 ) {
#writeLogln("Removed Zip $sSrcFile.");
writeLogln("Fail to upload: Removed Zip $sFile."); } else {
#
# delete flagfile after fail to upload if (unlink($sFlagFilePathSrc)) {
die("Error Removing Zip $sSrcFile: $!"); }

 #
#
# #}
writeLogln("Fail to upload: Removed FlagFile - ". basename $sFlagFilePathSrc); } else {
die("Error Removing FlagFile - $sFlagFilePathSrc: $!.");
#sendMail('Warn',$sErrMsg); sendMail($sErrMsg);
} # if ftp failed
}#if select NVL(count(t.sec_access_num),0) from pod_sys.T_MANUL_SAN_PREPRC t else{
writeLogln("No Record found to upload in Database for $sSAN.");
sendMail("No Record found to upload in Database for $sSAN."); }# else for select NVL(count(t.sec_access_num),0) from
pod_sys.T_MANUL_SAN_PREPRC t }
}
writeLogln("Scanned $sLocalDir."); }
sub RollBack($$$){ my($sSAN,$sSANsize,$sSANlastmodtime) = @_;
#roll back database entry
my $sql = qq/ BEGIN
P_MANUL_SAN_PREPRC(p_san=> '$sSAN',p_loadtype=>'U',p_timestamp=> sysdate, p_filesize=> $sSANsize, p_lastmodtime=>
to_date('$sSANlastmodtime','MM-DD-YYYY HH24:MI:SS'),p_uploadtype=>'HTML',p_rollback=>'1');
if ($DBI::err) {
writeLog($DBI::errstr); }
eval{
}; if($@)
writeLog("Executing Main SQL for Rollback \n");
$sth->execute; $sth->finish();
END; /;
my $sth = $dbh->prepare($sql);
{
writeLog("Rollback Database Entry Fail for san: '$sSAN': $@\n");
}

 }
sub moveAndExtractFiles() {
my ($sInDir, $sDstDir) = @_;
my (@files, $sFile, $sFlagFilePath); opendir FILES, $sInDir or die $!; @files = readdir FILES;
closedir FILES;
for $sFile(@files)
{
next if $sFile =~ /^\.*$/;
next if $sFile =~ /$sFlagFileSuffix_SanDirCopyDone/gi; next if $sFile =~ /$sFlagFileSuffix_SanTxtCopyDone/gi;
my $sSrcFile = "$sInDir/$sFile"; my $sDstFile = "$sDstDir/$sFile";
next if -d $sSrcFile;
my $sFlagFilePathSrc = $sSrcFile;
$sFlagFilePathSrc =~ s/.zip/$sFlagFileSuffix_SanTxtCopyDone/gi; next if !(-e $sFlagFilePathSrc);
move($sSrcFile, $sDstFile) or die "Error moving to $sDstDir: $!";
# delete flagfile
if (unlink($sFlagFilePathSrc)) {
writeLogln("Removed FlagFile - $sFlagFilePathSrc."); } else {
die("Error Removing FlagFile - $sFlagFilePathSrc: $!."); }
&writeLogln("Extracting zip file $sFile."); my $oZipper = Archive::Zip->new();
my $ret = $oZipper->read($sDstFile);
if ($ret != AZ_OK) {
undef $oZipper; &writeLogln("Error in unzip."); next;
}
foreach my $file($oZipper->memberNames) {
my $strUnzipFile = "$sDstDir/$file";
$ret = $oZipper->extractMember($file, $strUnzipFile);
die "Failed to extract $file from zip $sDstFile: $ret" if ($ret != AZ_OK);
}
# delete zip file

 my $nRet = unlink($sDstFile); if ( $nRet == 1 ) {
writeLogln("Removed Zip $sDstFile."); } else {
die("Error Removing Zip $sDstFile: $!"); }
}
writeLogln("Extraction completed."); }
#
# Used only for copying HTML manual corrected files #
sub copyToAutomatedValidator()
{
my ($sInDir, $sDstDir) = @_; my (@files, $sFile, $sErrFile); opendir FILES, $sInDir or die $!; @files = readdir FILES;
closedir FILES;
for $sFile(@files)
{
next if $sFile =~ /^\.*$/;
my $sSrcFile = "$sInDir/$sFile"; my $sDstFile = "$sDstDir/$sFile";
next if -d $sSrcFile;
&writeLogln("Moving file $sFile to Automated Validator pick folder");
move($sSrcFile, $sDstFile) or die "Error moving to $sDstDir: $!"; #
# Remove corresponding error file.
#
$sErrFile = "$sHTMLErrorFilesDir/$sFile"; if ( -e $sErrFile)
{
} }
}
my $nRet = unlink($sErrFile); if ( $nRet == 1 ) {
writeLogln("Removed Error file $sErrFile."); } else {
die("Error Removing Error file $sErrFile: $!"); }

 sub updatePNetFilingSizes() {
my $dbh = DBI->connect("dbi:Oracle:PNet", "PNet_Sys", "nr1048pnet", {RaiseError => 1});
my $sqls = qq{ SELECT DISTINCT Sec_Access_Num FROM Filing WHERE Sec_Access_Num>'0000000001' AND Filing_Size=0 };
my $sth = $dbh->prepare($sqls); $sth->execute();
while(my $rowref = $sth->fetchrow_arrayref) {
my $nFilingSize = -s "$sPNetDir/$rowref->[0].txt";
if ($nFilingSize > 0) {
my $sqlu = qq{ UPDATE Filing SET Filing_Size=$nFilingSize WHERE
Sec_Access_Num='$rowref->[0]' }; writeLogln("$sqlu");
$dbh->do($sqlu); }
}
$dbh->disconnect; }
sub loginToFTP() {
my $ping_obj = Net::Ping->new('icmp');
if ($ping_obj->ping($sFTPURL)) {
&writeLogln("FTP can be connected as it is reachable."); } else {
$FailCounter=$FailCounter+1;
print "Not able to reach FTP Site. \n"; &writeLogln("Not able to reach FTP Site."); if($FailCounter < 4){
sleep(20);
loginToFTP(); }
else{
die "Not able to connect FTP site.";
} }
my $ftp = Net::FTP->new($sFTPURL);
my $r = $ftp->login($sFTPUser,$sFTPPassword) or die "Not able to Instantiate FTP.";
if ($r ne 1) {

 &writeLogln("Could not login to FTP.");
die "Could not login to FTP."; }
&writeLogln("Logged into FTP."); $ftp->binary();
return $ftp;
}
sub writeLog($) {
#print @_;
open LOG, ">>$logfile" or warn $!; print LOG @_;
close LOG;
}
# get records from database using given SQL sub getDBRows($$)
{
my ($dbh, $sSQL) = @_;
my $sth = $dbh->prepare($sSQL); $sth->execute();
return $sth->fetchall_arrayref();
}
# Write a line of string to log file sub writeLogln($)
{
my ($text) = @_;
my ($sec, $min, $hr, $mday, $mon, $yr, $wday, $yda, $isdst) = localtime;
my $time = sprintf("%04d-%02d-%02d %02d:%02d:%02d ", $yr+1900, $mon+1, $mday, $hr,
$min, $sec);
writeLog($time . "" . "$text\n");
}
# Old of Sendmail commented, replaced with sendmail from executestoredprocedure.pl #sub sendMailold($$)
#{
# my ($sMsgType,$strMsg) = @_;
# my ($sec, $min, $hr, $mday, $mon, $yr, $wday, $yda, $isdst) = localtime;
# my $time = sprintf("%04d%02d%02d%02d%02d%02d", $yr+1900, $mon+1, $mday, $hr, $min, $sec);
# my $datetime = sprintf("%02d/%02d/%04d %02d:%02d:%02d %s", $mon+1, $mday, $yr+1900, $hr, $min, $sec, ($isdst)?'EDT':'EST');

 # my $sMailFile = "$sLogDir/$time.eml";
# my $sSubject = "";
# my $sMail = "";
# if ( $sMsgType eq 'Warn' )
#{
# $sSubject .= "\nImportance: High";
# $sSubject .= "\nSubject: TRW File Transfer ($sProcessOption) Warning at $datetime\nContent-Type:text/plain\n\n";
# $sMail = "TRW File Transfer ($sProcessOption) warning:\n\n$strMsg\n\n"; #}
# else
#{
# $sSubject .= "\nImportance: High";
# $sSubject .= "\nSubject: TRW File Transfer ($sProcessOption) Failed at $datetime\nContent-Type:text/plain\n\n";
# $sMail = "TRW File Transfer ($sProcessOption) failed:\n\n$strMsg\n\n"; #}
# open MAIL, ">$sMailFile";
# print MAIL $sMailingList, $sSubject, $sMail;
# close MAIL;
# my $r = copy($sMailFile, "$sPickupDir/$time.eml");
# writeLogln("An email has been sent.") if ($r==1); #}
# Sends Mail sub sendMail($) {
my ($errormsg) = @_;
my ($sec, $min, $hr, $mday, $mon, $yr, $wday, $yda, $isdst) = localtime;
my $time = sprintf("%04d%02d%02d%02d%02d%02d", $yr+1900, $mon+1, $mday, $hr, $min,
$sec);
my $datetime = sprintf("%02d/%02d/%04d %02d:%02d:%02d %s", $mon+1, $mday, $yr+1900,
$hr, $min, $sec, ($isdst)?'EDT':'EST');
my $sDate = sprintf("%02d/%02d/%04d", $mon+1, $mday, $yr+1900); my $sToSend = $sTo;
my $sCcSend = $sCc;
my $sBody;
$sMail = getlogin.'@'.hostname."\n$sMail"; if ($errormsg) {
$sMail = qq{$sSubject stopped due to the following error:\n$errormsg\n$sMail}; &writeLog(qq{\n$sSubject stopped due to the following error:\n$errormsg});
$sFrom = $sErrorFrom; $sToSend = $sErrorTo;

 $sCcSend = $sErrorCc;
$sSubject = "Failed : $sSubject"; }
$sBody = qq{\n<html><body>$sMail</body></html>}; $sBody =~ s/\n/<BR>\n/gs;
$sMail = '';
my $msg = MIME::Lite->new(
From
To
Cc
Subject => "$sSubject $sDate", Type => 'multipart/mixed');
$msg->add('Importance', 'High') if $errormsg;
$msg->attach(Type => 'text/html', Data => $sBody);
$msg->send('smtp', $sSMTPServer, Timeout=>60);
&writeLog("A mail has been sent to the persons specified in the mailing list.\n"); }
eval{ main;
};
# Errors will be Logged to Log File and also to Email File if ($@) {
print($@);
writeLogln($@);
# sendMail('Error',$@); sendMail($@);
$dbh->disconnect; }
############################################################################ ##
## Project: Prospectus Net 2000
##
## Document: ##
## Version: ##
## Author(s):
TRWFileTransfers.pl 1.0
Kesav Veera
=> $sFrom, => $sToSend,
=> $sCcSend,

##
## Date: 07/20/2010 ##
## Comment(s): Script to transfer filings (to and from India) ##
## ID:
## Version:
## LastEdit:
## ############################################################################ #
# Revision History:
# -----------------
# $Log: /ProspectusExpress/PNet2000/TRWFileTransfers $ #
# 07-Jul-2015 Introduced ping FTP site functionality. Om Prakash Singh #
# Script to copy/upload PNet Filings to PNet, PE directories
#
# ############################################################################
