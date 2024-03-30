﻿#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3				// Use modern global access method and strict wave access
#pragma DefaultTab={3,20,4}		// Set default tab width in Igor Pro 9 and later

/// new fastDAC code, implementing Ovi's API

////////////////////
//// Connection ////
////////////////////


function openFastDAC(IDname, portnum [verbose])
	// open/test a connection to the LS37X RPi interface written by Ovi
	//      the whole thing _should_ work for LS370 and LS372
	// instrID is the name of the global variable that will be used for communication
	// http_address is exactly what it sounds like
	//	it should look something like this: http://lcmi-docs.qdev-h101.lab:12441/api/v1/

	// verbose=0 will not print any information about the connection


	string IDname
	string portnum
	variable verbose
	
	string http_address = "http://lcmi-docs.qdev-h101.lab:"+portnum+"/api/v1/"


	if(paramisdefault(verbose))
		verbose=1
	elseif(verbose!=1)
		verbose=0
	endif

	string comm = ""
	sprintf comm, "instrID=%s,url=%s" IDname, http_address
	string response = ""

	openHTTPinstr(comm, verbose=verbose)  // Sets svar (instrID) = url
	//scf_addFDinfos(IDname,http_address,8,4)

	if (verbose==1)
		response=getHTTP(http_address,"idn","");
		print getjsonvalue(response,"idn")
	endif
end




function initFastDAC()
wave/t ADC_channel, DAC_channel, DAC_label


	// hardware limit (mV)
	variable i=0, numDevices = dimsize(ADC_channel,0)/4
	variable numDACCh=dimsize(DAC_channel,0), numADCCh=numDACch/2;
	
	// create waves to hold control info
	variable oldinit = scfw_fdacCheckForOldInit(numDACCh,numADCCh)

	// create GUI window
	string cmd = ""
	//variable winsize_l,winsize_r,winsize_t,winsize_b
	getwindow/z ScanControllerFastDAC wsizeRM
	killwindow/z ScanControllerFastDAC
	//sprintf cmd, "FastDACWindow(%f,%f,%f,%f)", v_left, v_right, v_top, v_bottom
	//execute(cmd)
	execute("after1()")
end



window FastDACWindow(v_left,v_right,v_top,v_bottom) : Panel
	variable v_left,v_right,v_top,v_bottom
	PauseUpdate; Silent 1 // pause everything else, while building the window
	
	NewPanel/w=(0,0,1010,585)/n=ScanControllerFastDAC
	if(v_left+v_right+v_top+v_bottom > 0)
		MoveWindow/w=ScanControllerFastDAC v_left,v_top,V_right,v_bottom
	endif
	ModifyPanel/w=ScanControllerFastDAC framestyle=2, fixedsize=1
	SetDrawLayer userback
	SetDrawEnv fsize=25, fstyle=1
	DrawText 160, 45, "DAC"
	SetDrawEnv fsize=25, fstyle=1
	DrawText 650, 45, "ADC"
	DrawLine 385,15,385,575 
	DrawLine 395,415,1000,415 /////EDIT 385-> 415
	DrawLine 355,415,375,415
	DrawLine 10,415,220,415
	SetDrawEnv dash=1
	Drawline 395,333,1000,333 /////EDIT 295 -> 320
	// DAC, 12 channels shown
	SetDrawEnv fsize=14, fstyle=1
	DrawText 15, 70, "Ch"
	SetDrawEnv fsize=14, fstyle=1
	DrawText 50, 70, "Output"
	SetDrawEnv fsize=14, fstyle=1
	DrawText 120, 70, "Limit"
	SetDrawEnv fsize=14, fstyle=1
	DrawText 220, 70, "Label"
	SetDrawEnv fsize=14, fstyle=1
	DrawText 287, 70, "Ramprate"
	ListBox fdaclist,pos={10,75},size={360,300},fsize=14,frame=2,widths={30,70,100,65} 
	ListBox fdaclist,listwave=root:fdacvalstr,selwave=root:fdacattr,mode=1
	Button updatefdac,pos={50,384},size={65,20},proc=scfw_update_fdac,title="Update" 
	Button fdacramp,pos={150,384},size={65,20},proc=scfw_update_fdac,title="Ramp"
	Button fdacrampzero,pos={255,384},size={80,20},proc=scfw_update_fdac,title="Ramp all 0" 
	// ADC, 8 channels shown
	SetDrawEnv fsize=14, fstyle=1
	DrawText 405, 70, "Ch"
	SetDrawEnv fsize=14, fstyle=1
	DrawText 450, 70, "Input (mV)"
	SetDrawEnv fsize=14, fstyle=1, textrot = -60
	DrawText 550, 75, "Record"
	SetDrawEnv fsize=14, fstyle=1
	DrawText 590, 70, "Wave Name"
	SetDrawEnv fsize=14, fstyle=1
	DrawText 705, 70, "Calc Function"
	SetDrawEnv fsize=14, fstyle=1, textrot = -60
	DrawText 850, 75, "Notch"
	SetDrawEnv fsize=14, fstyle=1, textrot = -60
	DrawText 885, 75, "Demod"
	SetDrawEnv fsize=14, fstyle=1, textrot = -60
	DrawText 920, 75, "Harmonic"
	SetDrawEnv fsize=14, fstyle=1, textrot = -60
	DrawText 950, 75, "Resamp"
	ListBox fadclist,pos={400,75},size={600,180},fsize=14,frame=2,widths={30,70,30,95,100,30,30,20,30} //added two widths for resample and notch filter, changed listbox size, demod
	
	
	ListBox fadclist,listwave=root:fadcvalstr,selwave=root:fadcattr,mode=1
	button updatefadc,pos={400,265},size={90,20},proc=scfw_update_fadc,title="Update ADC"
	checkbox sc_plotRawBox,pos={505,265},proc=scw_CheckboxClicked,variable=sc_plotRaw,side=1,title="\Z14Plot Raw"
	checkbox sc_demodyBox,pos={585,265},proc=scw_CheckboxClicked,variable=sc_demody,side=1,title="\Z14Save Demod.y"
	checkbox sc_hotcoldBox,pos={823,302},proc=scw_CheckboxClicked,variable=sc_hotcold,side=1,title="\Z14 Hot/Cold"
	SetVariable sc_hotcolddelayBox,pos={908,300},size={70,20},value=sc_hotcolddelay,side=1,title="\Z14Delay"
	SetVariable sc_FilterfadcBox,pos={828,264},size={150,20},value=sc_ResampleFreqfadc,side=1,title="\Z14Resamp Freq ",help={"Re-samples to specified frequency, 0 Hz == no re-sampling"} /////EDIT ADDED
	SetVariable sc_demodphiBox,pos={705,264},size={100,20},value=sc_demodphi,side=1,title="\Z14Demod \$WMTEX$ \Phi $/WMTEX$"//help={"Re-samples to specified frequency, 0 Hz == no re-sampling"} /////EDIT ADDED
	SetVariable sc_nfreqBox,pos={500,300},size={150,20}, value=sc_nfreq ,side=1,title="\Z14 Notch Freqs" ,help={"seperate frequencies (Hz) with , "}
	SetVariable sc_nQsBox,pos={665,300},size={140,20}, value=sc_nQs ,side=1,title="\Z14 Notch Qs" ,help={"seperate Qs with , "}
	DrawText 807,277, "\Z14\$WMTEX$ {}^{o} $/WMTEX$" 
	DrawText 982,283, "\Z14Hz" 
	
	//popupMenu fadcSetting1,pos={420,345},proc=scfw_scfw_update_fadcSpeed,mode=1,title="\Z14FD1 speed",size={100,20},value=sc_fadcSpeed1 
	//popupMenu fadcSetting2,pos={620,345},proc=scfw_scfw_update_fadcSpeed,mode=1,title="\Z14FD2 speed",size={100,20},value=sc_fadcSpeed2 
	//popupMenu fadcSetting3,pos={820,345},proc=scfw_scfw_update_fadcSpeed,mode=1,title="\Z14FD3 speed",size={100,20},value=sc_fadcSpeed3 
	//popupMenu fadcSetting4,pos={420,375},proc=scfw_scfw_update_fadcSpeed,mode=1,title="\Z14FD4 speed",size={100,20},value=sc_fadcSpeed4 
	//popupMenu fadcSetting5,pos={620,375},proc=scfw_scfw_update_fadcSpeed,mode=1,title="\Z14FD5 speed",size={100,20},value=sc_fadcSpeed5 
	//popupMenu fadcSetting6,pos={820,375},proc=scfw_scfw_update_fadcSpeed,mode=1,title="\Z14FD6 speed",size={100,20},value=sc_fadcSpeed6 
//	DrawText 545, 362, "\Z14Hz"
//	DrawText 745, 362, "\Z14Hz" 
//	DrawText 945, 362, "\Z14Hz" 
//	DrawText 545, 392, "\Z14Hz" 
//	DrawText 745, 392, "\Z14Hz" 
//	DrawText 945, 392, "\Z14Hz" 

	// identical to ScanController window
	// all function calls are to ScanController functions
	// instrument communication
	
	SetDrawEnv fsize=14, fstyle=1
	DrawText 415, 445, "Connect Instrument" 
	SetDrawEnv fsize=14, fstyle=1 
	DrawText 635, 445, "Open GUI" 
	SetDrawEnv fsize=14, fstyle=1
	DrawText 825, 445, "Log Status" 
	ListBox sc_InstrFdac,pos={400,450},size={600,100},fsize=14,frame=2,listWave=root:sc_Instr,selWave=root:instrBoxAttr,mode=1, editStyle=1

	// buttons  
	button connectfdac,pos={400,555},size={110,20},proc=scw_OpenInstrButton,title="Connect Instr" 
	button guifdac,pos={520,555},size={110,20},proc=scw_OpenGUIButton,title="Open All GUI" 
	button killaboutfdac, pos={640,555},size={120,20},proc=sc_controlwindows,title="Kill Sweep Controls" 
	button killgraphsfdac, pos={770,555},size={110,20},proc=scw_killgraphs,title="Close All Graphs" 
	button updatebuttonfdac, pos={890,555},size={110,20},proc=scw_updatewindow,title="Update" 

	// helpful text
	//DrawText 820, 595, "Press Update to save changes."
	
	
	/// Lock in stuff
	tabcontrol tb, proc=TabProc , pos={230,410},size={130,22},fsize=13, appearance = {default}
	tabControl tb,tabLabel(0) = "Lock-In" 
	tabControl tb,tabLabel(1) = "AWG"
	
	tabcontrol tb2, proc=TabProc2 , pos={44,423},size={180,22},fsize=13, appearance = {default}, disable = 1
	tabControl tb2,tabLabel(0) = "Set AW" 
	tabControl tb2,tabLabel(1) = "AW0"
	tabControl tb2,tabLabel(2) = "AW1"
	
	button setupLI,pos={10,510},size={55,40},proc=scw_setupLockIn,title="Set\rLock-In"
	
	ListBox LIlist,pos={70,455},size={140,95},fsize=14,frame=2,widths={60,40}
	ListBox LIlist,listwave=root:LIvalstr,selwave=root:LIattr,mode=1
	
	ListBox LIlist0,pos={223,479},size={147,71},fsize=14,frame=2,widths={40,60}
	ListBox LIlist0,listwave=root:LIvalstr0,selwave=root:LIattr0,mode=1
	
	titlebox AW0text,pos={223,455},size={60,20},Title = "AW0",frame=0, fsize=14
	//awgLIvalstr
	//AWGvalstr
	ListBox awglist,pos={70,455},size={140,120},fsize=14,frame=2,widths={40,60}, disable = 1
	ListBox awglist,listwave=root:awgvalstr,selwave=root:awgattr,mode=1
	
	ListBox awglist0,pos={70,455},size={140,120},fsize=14,frame=2,widths={40,60}, disable = 1
	ListBox awglist0,listwave=root:awgvalstr0,selwave=root:awgattr0,mode=1
	
	ListBox awglist1,pos={70,455},size={140,120},fsize=14,frame=2,widths={40,60}, disable = 1
	ListBox awglist1,listwave=root:awgvalstr1,selwave=root:awgattr1,mode=1
	
	ListBox awgsetlist,pos={223,479},size={147,71},fsize=14,frame=2,widths={50,40}, disable = 1
	ListBox awgsetlist,listwave=root:awgsetvalstr,selwave=root:awgsetattr,mode=1
	
	titleBox freqtextbox, pos={10,480}, size={100, 20}, title="Frequency", frame = 0, disable=1
	titleBox Hztextbox, pos={48,503}, size={40, 20}, title="Hz", frame = 0, disable=1
	
	
	///AWG
	button clearAW,pos={10,555},size={55,20},proc=scw_clearAWinputs,title="Clear", disable = 1
	button setupAW,pos={10,525},size={55,20},proc=scw_setupsquarewave,title="Create", disable = 1
	SetVariable sc_wnumawgBox,pos={10,499},size={55,25},value=sc_wnumawg,side=1,title ="\Z14AW", help={"0 or 1"}, disable = 1
	SetVariable sc_freqBox0, pos={6,500},size={40,20}, value=sc_freqAW0 ,side=0,title="\Z14 ", disable = 1, help = {"Shows the frequency of AW0"}
	SetVariable sc_freqBox1, pos={6,500},size={40,20}, value=sc_freqAW1 ,side=1,title="\Z14 ", disable = 1, help = {"Shows the frequency of AW1"}
	button setupAWGfdac,pos={260,555},size={110,20},proc=scw_setupAWG,title="Setup AWG", disable = 1
	
	

	 

	
endmacro

window scfw_fdacInitWindow() : Panel
	PauseUpdate; Silent 1 // building window
	NewPanel /W=(100,100,400,630) // window size
	ModifyPanel frameStyle=2
	SetDrawLayer UserBack
	SetDrawEnv fsize= 25,fstyle= 1
	DrawText 20, 45,"Choose FastDAC init" // Headline
	SetDrawEnv fsize= 14,fstyle= 1
	DrawText 40,80,"Old init"
	SetDrawEnv fsize= 14,fstyle= 1
	DrawText 170,80,"Default"
	ListBox initlist,pos={10,90},size={280,390},fsize=16,frame=2
	ListBox initlist,fStyle=1,listWave=root:fdacinit,mode= 0
	Button old_fdacinit,pos={40,490},size={70,20},proc=scfw_fdacAskUserUpdate,title="OLD INIT"
	Button default_fdacinit,pos={170,490},size={70,20},proc=scfw_fdacAskUserUpdate,title="DEFAULT"
endmacro


function scfw_fdacAskUserUpdate(action) : ButtonControl
	string action
	variable/g fdac_answer

	strswitch(action)
		case "old_fdacinit":
			fdac_answer = 1
			dowindow/k scfw_fdacInitWindow
			break
		case "default_fdacinit":
			fdac_answer = -1
			dowindow/k scfw_fdacInitWindow
			break
	endswitch
end



Function RampMultipleFDAC(string channels, variable setpoint, [variable ramprate, string setpoints_str])
    // This function ramps multiple FastDAC channels to given setpoint(s) at a specified ramp rate.
    // Parameters:
    // channels - A comma-separated list of channels to be ramped.
    // setpoint - A common setpoint to ramp all channels to (ignored if setpoints_str is provided).
    // ramprate - The ramp rate in mV/s for all channels. If not specified, uses each channel's configured ramp rate.
    // setpoints_str - An optional comma-separated list of setpoints, allowing individual setpoints for each channel.

 
    
    // If ramprate is not specified or not a number, default to 0 (indicating use of configured ramp rates)
    ramprate = numtype(ramprate) == 0 ? ramprate : 0

    // Convert channel identifiers to numbers, supporting both numerical IDs and named channels
    channels = scu_getChannelNumbers(channels)
    
    // Abort if the number of channels and setpoints do not match when individual setpoints are provided
    if (!paramIsDefault(setpoints_str) && (itemsInList(channels, ",") != itemsInList(setpoints_str, ","))) 
        abort "ERROR[RampMultipleFdac]: Number of channels does not match number of setpoints in setpoints_str"    
    endif
    
    // Initialize variables for the loop
    Variable i = 0, channel, nChannels = ItemsInList(channels, ",")
    Variable channel_ramp  // Not used, consider removing if unnecessary
    
    // Loop through each channel to apply the ramp
    for (i = 0; i < nChannels; i += 1)
        // If individual setpoints are provided, override the common setpoint with the specific value for each channel
        if (!paramIsDefault(setpoints_str)) 
            setpoint = str2num(StringFromList(i, setpoints_str, ","))
        endif
        
        // Extract the channel number from the list and ramp to the setpoint
        channel = str2num(StringFromList(i, channels, ","))
        fd_rampOutputFDAC(channel, setpoint, ramprate)  // Ramp the channel to the setpoint at the specified rate
    endfor
End


Function fd_rampOutputFDAC(int channel, variable setpoint, variable ramprate) // Units: mV, mV/s
    // This function ramps one FD DAC channel to a specified setpoint at a given ramprate.
    // It checks that both the setpoint and ramprate are within their respective limits before proceeding.

    // Access the global wave containing FDAC channel settings
    Wave/T fdacvalstr
    
    // Ensure the output is within the hardware's permissible limits
    Variable output = check_fd_limits(channel, setpoint)
    
    // Check if the requested ramprate is within the software limit
    // If not, the maximum permissible ramprate is used instead
    If (ramprate > str2num(fdacvalstr[channel][4]) || numtype(ramprate) != 0)
        printf "[WARNING] \"fd_rampOutputFDAC\": Ramprate of %.0fmV/s requested for channel %d. Using max_ramprate of %.0fmV/s instead\n", ramprate, channel, str2num(fdacvalstr[channel][4])
        ramprate = str2num(fdacvalstr[channel][4])
        
        // If after adjustment, the ramprate is still not a numeric type, abort the operation
        If (numtype(ramprate) != 0)
            Abort "ERROR[fd_rampOutputFDAC]: Bad ramprate in ScanController_Fastdac window for channel " + num2str(channel)
        EndIf
    EndIf
    
    // Ramp the DAC channel to the desired output with the validated ramprate
    set_one_FDACChannel(channel, output, ramprate)
    
    // Update the DAC value in the FastDAC panel to reflect the change
    Variable currentoutput = get_one_FDACChannel(channel)
    scfw_updateFdacValStr(channel, currentoutput, update_oldValStr=1)
End

function check_fd_limits(int channel, variable output)
	// check that output is within software limit
	// overwrite output to software limit and warn user
	wave/t fdacvalstr

	string softLimitPositive = "", softLimitNegative = "", expr = "(-?[[:digit:]]+),\s*([[:digit:]]+)"
	splitstring/e=(expr) fdacvalstr[channel][2], softLimitNegative, softLimitPositive
	if(output < str2num(softLimitNegative) || output > str2num(softLimitPositive))
		switch(sign(output))
			case -1:
				output = str2num(softLimitNegative)
				break
			case 1:
				if(output != 0)
					output = str2num(softLimitPositive)
				else
					output = 0
				endif
				break
		endswitch
		string warn
		sprintf warn, "[WARNING] \"fd_rampOutputFDAC\": Output voltage must be within limit. Setting channel %d to %.3fmV\n", channel, output
		print warn
	endif

	return output
end


//////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////// AWG stuff////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////



function fd_initGlobalAWG()
	Struct AWGVars S
	// Set empty strings instead of null
	S.AW_waves   = ""
	S.AW_dacs    = ""
	S.AW_dacs2   = ""
	S.channels_AW0   = ""
	S.channels_AW1   = ""
	S.channelIDs = ""
	S.InstrIDs   = "" 
	
	fd_setGlobalAWG(S)
end


function fd_setGlobalAWG(S)
	// Function to store values from AWG_list to global variables/strings/waves
	// StructPut ONLY stores VARIABLES so have to store other parts separately
	struct AWGVars &S

	// Store String parts  
	make/o/t fd_AWGglobalStrings = {S.AW_Waves, S.AW_dacs, S.AW_dacs2, S.channels_AW0, S.channels_AW1, S.channelIDs, S.InstrIDs}

	// Store variable parts
	make/o fd_AWGglobalVars = {S.initialized, S.use_AWG, S.lims_checked, S.waveLen, S.numADCs, S.samplingFreq,\
		S.measureFreq, S.numWaves, S.numCycles, S.numSteps, S.maxADCs}
end


function SetAWG(A, state)
	// Set use_awg state to 1 or 0
	struct AWGVars &A
	variable state
	
	if (state != 0 && state != 1)
		abort "ERROR[SetAWGuseState]: value must be 0 or 1"
	endif
	if (A.initialized == 0 || numtype(strlen(A.AW_Waves)) != 0 || numtype(strlen(A.AW_dacs)) != 0)
		fd_getGlobalAWG(A)
	endif
	A.use_awg = state
	fd_setGlobalAWG(A)
end


function fd_getGlobalAWG(S)
	// Function to get global values for AWG_list that were stored using set_global_AWG_list()
	// StructPut ONLY gets VARIABLES
	struct AWGVars &S
	// Get string parts
	wave/T t = fd_AWGglobalStrings
	
		if (!WaveExists(t))
		fd_initGlobalAWG()
		wave/T t = fd_AWGglobalStrings
	endif
	
	S.AW_waves = t[0]
	S.AW_dacs = t[1]
	S.AW_dacs2 = t[2]
	S.channels_AW0 = t[3]
	S.channels_AW1 = t[4]
	S.channelIDs = t[5]
	S.instrIDs = t[6]

	// Get variable parts
	wave v = fd_AWGglobalVars
	S.initialized = v[0]
	S.use_AWG = v[1]  
	S.lims_checked = 0 // Always initialized to zero so that checks have to be run before using in scan (see SetCheckAWG())
	S.waveLen = v[3]
	S.numADCs = v[4]
	S.samplingFreq = v[5]
	S.measureFreq = v[6]
	S.numWaves = v[7]
	S.numCycles = v[8]
	S.numSteps = v[9]
	S.maxADCs = v[10]
	
end

//////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////// End of AWG stuff//////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////




function initScanVarsFD(S, startx, finx, [channelsx, numptsx, sweeprate, duration, rampratex, delayx, starty, finy, channelsy, numptsy, rampratey, delayy, startxs, finxs, startys, finys, x_label, y_label, alternate,  interlaced_channels, interlaced_setpoints, comments, x_only, use_awg])
 // Initializes scan variables for FastDAC scanning operations.
    // The function allows setting up both x and y dimensions with various parameters,
    // including starting/ending points, channel identifiers, sweep rates, and more.
    // 
    // PARAMETERS:
    // S: ScanVars structure passed by reference to be initialized.
    // startx, finx: Starting and ending points for the x dimension.
    // channelsx, channelsy: Comma-separated strings of channels to be scanned in the x and y dimensions.
    // numptsx, numptsy: Number of points to be scanned in the x and y dimensions.
    // sweeprate: The sweep rate for the scan.
    // duration: The duration of the scan.
    // rampratex, rampratey: Ramp rates for the x and y dimensions.
    // delayx, delayy: Delays for the x and y dimensions.
    // startxs, finxs, startys, finys: Alternative to startx/finx for specifying multiple start/end points for each channel.
    // x_label, y_label: Labels for the x and y dimensions.
    // alternate: Flag to indicate alternate scanning.
    // interlaced_channels, interlaced_setpoints: Parameters for interlaced scanning.
    // comments: Comments or notes regarding the scan.
    // x_only: Flag to indicate if only x dimension is used.
    // use_awg: Flag to indicate if AWG is used in the scan.

    struct ScanVars &S
    variable x_only, startx, finx, numptsx, delayx, rampratex
    variable starty, finy, numptsy, delayy, rampratey
	 variable sweeprate  // If start != fin numpts will be calculated based on sweeprate
	 variable duration   // numpts will be caluculated to achieve duration
    variable alternate, use_awg
    string channelsx, channelsy
    string startxs, finxs, startys, finys
    string  x_label, y_label
    string interlaced_channels, interlaced_setpoints
    string comments
	
    // Defaulting optional string parameters to empty if not provided
	channelsy = selectString(paramIsDefault(channelsy), channelsy, "")
	startys = selectString(paramIsDefault(startys), startys, "")
	finys = selectString(paramIsDefault(finys), finys, "")
	y_label = selectString(paramIsDefault(y_label), y_label, "")	

	channelsx = selectString(paramIsDefault(channelsx), channelsx, "")
	startxs = selectString(paramIsDefault(startxs), startxs, "")
	finxs = selectString(paramIsDefault(finxs), finxs, "")
	x_label = selectString(paramIsDefault(x_label), x_label, "")
	
	interlaced_channels = selectString(paramisdefault(interlaced_channels), interlaced_channels, "")
	interlaced_setpoints = selectString(paramisdefault(interlaced_setpoints), interlaced_setpoints, "")

	comments = selectString(paramIsDefault(comments), comments, "")
	x_only = paramisdefault(x_only) ? 1 : x_only
	use_awg = paramisdefault(use_awg) ? 0 : use_awg  


	// Standard initialization
	initScanVars(S, startx=startx, finx=finx, channelsx=channelsx, numptsx=numptsx, delayx=delayx, rampratex=rampratex,\
	starty=starty, finy=finy, channelsy=channelsy, numptsy=numptsy, rampratey=rampratey, delayy=delayy, \
	x_label=x_label, y_label=y_label, startxs=startxs, finxs=finxs, startys=startys, finys=finys, alternate=alternate,\
	interlaced_channels=interlaced_channels, interlaced_setpoints=interlaced_setpoints, comments=comments)
	
	
	// Additional intialization for fastDAC scans
	S.sweeprate = sweeprate
	S.duration = duration
   S.adcList = scf_getRecordedFADCinfo("channels")
   S.using_fastdac = 1

//   	// Sets channelsx, channelsy to be lists of channel numbers instead of labels
   scv_setChannels(S, channelsx, channelsy, fastdac=1)  
     
   	// Get Labels for graphs
   	S.x_label = selectString(strlen(x_label) > 0, scu_getDacLabel(S.channelsx, fastdac=1), x_label)  // Uses channels as list of numbers, and only if x_label not passed in
   	if (S.is2d)
   		S.y_label = selectString(strlen(y_label) > 0, scu_getDacLabel(S.channelsy, fastdac=1), y_label) 
   	else
   		S.y_label = y_label
   	endif  		

   	// Sets starts/fins (either using starts/fins given or from single startx/finx given)
   // scv_setSetpoints(S, channelsx, startx, finx, channelsy, starty, finy, startxs, finxs, startys, finys) had to move this
	
	
	scv_setSetpoints(S, channelsx, startx, finx, channelsy, starty, finy, startxs, finxs, startys, finys)
	
	// Set variables with some calculation
    scv_setFreq(S=S) 		// Sets S.samplingFreq/measureFreq/numADCs	
    scv_setNumptsSweeprateDuration(S) 	// Checks that either numpts OR sweeprate OR duration was provided, and sets ScanVars accordingly
                                       // Note: Valid for start/fin only (uses S.startx, S.finx NOT S.startxs, S.finxs)
                                
   ///// for 2D scans //////////////////////////////////////////////////////////////////////////////////////////////////
   if(!x_only)
   		S.channelsy = scu_getChannelNumbers(channelsy)				// converting from channel labels to numbers
		S.y_label = scu_getDacLabel(S.channelsy)						// setting the y_label
   endif
   print S                                                        
end



///////////////////////
//// API functions ////
///////////////////////


//function set_one_fadcSpeed(int adcValue,variable speed)
//	svar fd
//	String cmd = "set-convert-time"
//	// Convert variables to strings and construct the JSON payload dynamically
//	String payload
//	payload = "{\"adc\": " + num2str(adcValue) + ", \"duration_us\": " + num2str(speed) + "}"
//	String headers = "accept: application/json\nContent-Type: application/json"
//	// Perform the HTTP PUT request
//	String response = putHTTP(instrID, cmd, payload, headers)
//	print response
//end
//
//
//function get_one_fadcSpeed(int adcValue)
//	svar fd
//	string	response=getHTTP(fd,"read-convert-time/"+num2str(adcValue),"");
//	string value
//	value=getjsonvalue(response,"durationUs")
//	variable speed = roundNum(1.0/str2num(value)*1.0e6,0)
//	return speed
//end
//
//function get_one_FADCChannel(int channel) // Units: mV
//	svar fd
//	string	response=getHTTP(fd,"get-adc/"+num2str(channel),"");print response
//	string adc
//	adc=getjsonvalue(response,"value")
//	return str2num(adc)
//end
//
//function get_one_FDACChannel(int channel) // Units: mV
//	svar fd
//	string	response=getHTTP(fd,"get-dac/"+num2str(channel),"");
//	string adc
//	adc=getjsonvalue(response,"value")
//	return str2num(adc)
//end

//function set_one_FDACChannel(int channel, variable setpoint, variable ramprate)
//	svar fd
//	String cmd = "smart-ramp-sync"
//	String payload
//	payload = "{\"dac\": " + num2str(channel) + ", \"setpoint_mv\": " + num2str(setpoint)+ ", \"rate_mv_s\": " + num2str(ramprate) + "}"
//	String headers = "accept: application/json\nContent-Type: application/json"
//	String response = postHTTP(fd, cmd, payload, headers)
//	print response
//end








function set_one_fadcSpeed(int adcValue,variable speed)
speed=gnoise(1)
return speed
end


function get_one_fadcSpeed(int adcValue)
variable speed=gnoise(1)
return speed
end

function get_one_FADCChannel(int channel) // Units: mV
variable speed=gnoise(1)
return speed
end

function get_one_FDACChannel(int channel) // Units: mV
variable speed=channel+gnoise(1)
return speed
end

function set_one_FDACChannel(int channel, variable setpoint, variable ramprate)
variable speed=gnoise(1)
return speed
end




///////////////////
//// Utilities ////
///////////////////
function fd_get_numpts_from_sweeprate(start, fin, sweeprate, measureFreq)
/// Convert sweeprate in mV/s to numptsx for fdacrecordvalues
	variable start, fin, sweeprate, measureFreq
	if (start == fin)
		abort "ERROR[fd_get_numpts_from_sweeprate]: Start == Fin so can't calculate numpts"
	endif
	variable numpts = round(abs(fin-start)*measureFreq/sweeprate)   // distance * steps per second / sweeprate
	return numpts
end

function fd_get_sweeprate_from_numpts(start, fin, numpts, measureFreq)
	// Convert numpts into sweeprate in mV/s
	variable start, fin, numpts, measureFreq
	if (numpts == 0)
		abort "ERROR[fd_get_numpts_from_sweeprate]: numpts = 0 so can't calculate sweeprate"
	endif
	variable sweeprate = round(abs(fin-start)*measureFreq/numpts)   // distance * steps per second / numpts
	return sweeprate
end

function fd_getmaxADCs(S)
	struct ScanVars &S
	variable maxADCs
	wave fadcattr
	wave numericwave
	string adcList = scf_getRecordedFADCinfo("channels")
	StringToListWave(adclist)
	numericwave=floor(numericwave/4)
	maxADCs=FindMaxRepeats(numericwave)
	S.numADCs=dimsize(numericwave,0)
	return maxADCs
end

