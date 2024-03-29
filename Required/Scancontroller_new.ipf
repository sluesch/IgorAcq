#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3				// Use modern global access method and strict wave access
#pragma DefaultTab={3,20,4}		// Set default tab width in Igor Pro 9 and later

function scfw_fdacCheckForOldInit(numDACCh,numADCCh)
	variable numDACCh, numADCCh

	variable response
	wave/z fdacvalstr
	wave/z old_fdacvalstr
	if(waveexists(fdacvalstr) && waveexists(old_fdacvalstr))
		response = scfw_fdacAskUser(numDACCh)
		if(response == 1)
			// Init at old values
			print "[FastDAC] Init to old values"
		elseif(response == -1)
			// Init to default values
			scfw_CreateControlWaves(numDACCh,numADCCh)
			print "[FastDAC] Init to default values"
		else
			print "[Warning] \"scfw_fdacCheckForOldInit\": Bad user input - Init to default values"
			scfw_CreateControlWaves(numDACCh,numADCCh)
			response = -1
		endif
	else
		// Init to default values
		scfw_CreateControlWaves(numDACCh,numADCCh)
		response = -1
	endif

	return response
end

function scfw_fdacAskUser(numDACCh)
	variable numDACCh
	wave/t fdacvalstr

	// can only init to old settings if the same
	// number of DAC channels are used
	if(dimsize(fdacvalstr,0) == numDACCh)
		make/o/t/n=(numDACCh) fdacdefaultinit = "0"
		duplicate/o/rmd=[][1] fdacvalstr ,fdacvalsinit
		concatenate/o {fdacvalsinit,fdacdefaultinit}, fdacinit
		execute("scfw_fdacInitWindow()")
		pauseforuser scfw_fdacInitWindow
		nvar fdac_answer
		return fdac_answer
	else
		return -1
	endif
end


function scfw_CreateControlWaves(numDACCh,numADCCh)
//creates all waves and strings necessary for initfastDAC()
	variable numDACCh,numADCCh

	// create waves for DAC part
	make/o/t/n=(numDACCh) fdacval0 = "0"				// Channel
	make/o/t/n=(numDACCh) fdacval1 = "0"				// Output /mV
	make/o/t/n=(numDACCh) fdacval2 = "-10000,10000"	// Limits /mV
	make/o/t/n=(numDACCh) fdacval3 = ""					// Labels
	make/o/t/n=(numDACCh) fdacval4 = "10000"			// Ramprate limit /mV/s
	variable i=0
	for(i=0;i<numDACCh;i+=1)
		fdacval0[i] = num2istr(i)
	endfor
	concatenate/o {fdacval0,fdacval1,fdacval2,fdacval3,fdacval4}, fdacvalstr
	duplicate/o/R=[][1] fdacvalstr, old_fdacvalstr
	make/o/n=(numDACCh) fdacattr0 = 0
	make/o/n=(numDACCh) fdacattr1 = 2
	concatenate/o {fdacattr0,fdacattr1,fdacattr1,fdacattr1,fdacattr1}, fdacattr

	//create waves for ADC part
	make/o/t/n=(numADCCh) fadcval0 = "0"	// Channel
	make/o/t/n=(numADCCh) fadcval1 = ""		// Input /mV  (initializes empty otherwise false reading)
	make/o/t/n=(numADCCh) fadcval2 = ""		// Record (1/0)
	make/o/t/n=(numADCCh) fadcval3 = ""		// Wave Name
	make/o/t/n=(numADCCh) fadcval4 = ""		// Calc (e.g. ADC0*1e-6)
	
	make/o/t/n=(numADCCh) fadcval5 = ""		// Resample (1/0) // Nfilter
	make/o/t/n=(numADCCh) fadcval6 = ""		// Notch filter (1/0) //Demod
	make/o/t/n=(numADCCh) fadcval7 = "1"	// Demod (1/0) //Harmonic
	make/o/t/n=(numADCCh) fadcval8 = ""		// Demod (1/0) // Resample
	
	for(i=0;i<numADCCh;i+=1)
		fadcval0[i] = num2istr(i)
		fadcval3[i] = "wave"+num2istr(i)
		fadcval4[i] = "ADC"+num2istr(i)
	endfor
	concatenate/o {fadcval0,fadcval1,fadcval2,fadcval3,fadcval4, fadcval5, fadcval6, fadcval7,fadcval8}, fadcvalstr // added 5 & 6 for resample and notch filter
	make/o/n=(numADCCh) fadcattr0 = 0
	make/o/n=(numADCCh) fadcattr1 = 2
	make/o/n=(numADCCh) fadcattr2 = 32
	concatenate/o {fadcattr0,fadcattr0,fadcattr2,fadcattr1,fadcattr1, fadcattr2, fadcattr2, fadcattr1, fadcattr2}, fadcattr // added fadcattr2 twice for two checkbox commands?
	
	
	// create waves for LI
	make/o/t/n=(4,2) LIvalstr
	LIvalstr[0][0] = "Amp"
	LIvalstr[1][0] = "Freq (Hz)"
	LIvalstr[2][0] = "Channels"
	LIvalstr[3][0] = "Cycles"
	LIvalstr[][1] = ""
	
	make/o/n=(4,2) LIattr = 0
	LIattr[][1] = 2
	
	make/o/t/n=(3,2) LIvalstr0
	LIvalstr0[0][0] = "Amp"
	LIvalstr0[0][1] = "Time (ms)"
	LIvalstr0[1,2][] = ""
	
	make/o/n=(3,2) LIattr0 = 0

	// create waves for AWG
	make/o/t/n=(11,2) AWGvalstr
	AWGvalstr[0][0] = "Amp"
	AWGvalstr[0][1] = "Time (ms)"
	AWGvalstr[1,10][] = ""
	make/o/n=(10,2) AWGattr = 2
	AWGattr[0][] = 0
	
	// AW0
	make/o/t/n=(11,2) AWGvalstr0
	AWGvalstr0[0][0] = "Amp"
	AWGvalstr0[0][1] = "Time (ms)"
	AWGvalstr0[1,10][] = ""
	make/o/n=(10,2) AWGattr0 = 0
	//AW1
	make/o/t/n=(11,2) AWGvalstr1
	AWGvalstr1[0][0] = "Amp"
	AWGvalstr1[0][1] = "Time (ms)"
	AWGvalstr1[1,10][] = ""
	make/o/n=(10,2) AWGattr1 = 0
	
	// create waves for AWGset
	make/o/t/n=(3,2) AWGsetvalstr
	AWGsetvalstr[0][0] = "AW0 Chs"
	AWGsetvalstr[1][0] = "AW1 Chs"
	AWGsetvalstr[2][0] = "Cycles"
	AWGsetvalstr[][1] = ""
	
	make/o/n=(3,2) AWGsetattr = 0
	AWGsetattr[][1] = 2
	
	variable /g sc_printfadc = 0
	variable /g sc_saverawfadc = 0
	variable /g sc_demodphi = 0
	variable /g sc_demody = 0
	variable /g sc_hotcold = 0
	variable /g sc_hotcolddelay = 0
	variable /g sc_plotRaw = 0
	variable /g sc_wnumawg = 0
	variable /g tabnumAW = 0
	variable /g sc_ResampleFreqfadc = 100 // Resampling frequency if using resampling
	string   /g sc_freqAW0 = ""
	string   /g sc_freqAW1 = ""
	string   /g sc_nfreq = "60,180,300"
	string   /g sc_nQs = "50,150,250"
	
	
	// instrument wave
	// make some waves needed for the scancontroller window
	variable /g sc_instrLimit = 20 // change this if necessary, seeems fine
	make /o/N=(sc_instrLimit,3) instrBoxAttr = 2
	make /t/o/N=(sc_instrLimit,3) sc_Instr

	sc_Instr[0][0] = "openMultipleFDACs(\"12441\", verbose=1)"
	//sc_Instr[1][0] = "openLS370connection(\"ls\", \"http://lksh370-xld.qdev-b111.lab:49300/api/v1/\", \"bfbig\", verbose=1)"
	//sc_Instr[2][0] = "openIPS120connection(\"ips1\",\"GPIB::25::INSTR\", 9.569, 9000, 182, verbose=0, hold = 1)"
	sc_Instr[0][2] = "getFDstatus(\"fd1\")"
	//sc_Instr[1][2] = "getls370Status(\"ls\")"
	//sc_Instr[2][2] = "getipsstatus(ips1)"
	//sc_Instr[3][2] = "getFDstatus(\"fd2\")"
	//sc_Instr[4][2] = "getFDstatus(\"fd3\")"


	// clean up
	killwaves fdacval0,fdacval1,fdacval2,fdacval3,fdacval4
	killwaves fdacattr0,fdacattr1
	killwaves fadcval0,fadcval1,fadcval2,fadcval3,fadcval4, fadcval5, fadcval6, fadcval7,fadcval8 // added 5,6 for cleanup
	killwaves fadcattr0,fadcattr1,fadcattr2
end

function scw_OpenInstrButton(action) : Buttoncontrol
	string action
	sc_openInstrConnections(1)
end







function scfw_update_fadc(action) : ButtonControl
	string action
	svar sc_fdackeys
	wave/t fadcvalstr
	variable i=0

	variable numADCCh
	numADCch = dimsize(fadcvalstr,0); 
	variable temp
	for(i=0;i<numADCCh;i+=1)
		temp= get_one_FADCChannel(i)
		fadcvalstr[i][1] = num2str(temp)
	endfor
end


function scfw_update_fdac(action) : ButtonControl
	string action
	svar sc_fdackeys
	wave/t fdacvalstr
	wave/t old_fdacvalstr
	scfw_update_all_fdac(option=action)
end



function scfw_update_all_fdac([option])
	// Ramps or updates all FastDac outputs
	string option // {"fdacramp": ramp all fastdacs to values currently in fdacvalstr, "fdacrampzero": ramp all to zero, "updatefdac": update fdacvalstr from what the dacs are currently at}
	wave/t fdacvalstr
	wave/t old_fdacvalstr
	wave/t DAC_channel

	if (paramisdefault(option))
		option = "fdacramp"
	endif
	
	// Either ramp fastdacs or update fdacvalstr
	variable i=0,j=0,output = 0, startCh = 0, numDACCh
	numDACCh = dimsize(DAC_channel,0)
	

			try
				strswitch(option)
					case "fdacramp":
						for(j=0;j<numDACCh;j+=1)
							output = str2num(fdacvalstr[j][1])
							if(output != str2num(old_fdacvalstr[j]))
								rampmultipleFDAC(num2str(j), output)
							endif
						endfor
						break
					case "fdacrampzero":
						for(j=0;j<numDACCh;j+=1)
							rampmultipleFDAC(num2str(j), 0)
						endfor
					break

					case "updatefdac":
						variable value
						for(j=0;j<numDACCh;j+=1)
							value=get_one_FDACChannel(j)
							scfw_updateFdacValStr(j, value, update_oldValStr=1)
						endfor
						break
				endswitch
			catch
			
				
				// silent abort
				abortonvalue 1,10
			endtry
		
	
end

function scfw_updateFdacValStr(channel, value, [update_oldValStr])
	// Update the global string(s) which store FastDAC values. Update the oldValStr if you know that is the current DAC output.
	variable channel, value, update_oldValStr

	// TODO: Add checks here
	// check value is valid (not NaN or inf)
	// check channel_num is valid (i.e. within total number of fastdac DAC channels)
	wave/t fdacvalstr
	fdacvalstr[channel][1] = num2str(value)
	if (update_oldValStr != 0)
		wave/t old_fdacvalstr
		old_fdacvalstr[channel] = num2str(value)
	endif
end




/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////// Common Scancontroller Functions /////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function sc_openInstrConnections(print_cmd)
	// open all VISA connections to instruments
	// this is a simple as running through the list defined
	//     in the scancontroller window
	variable print_cmd
	wave /T sc_Instr

	variable i=0
	string command = ""
	for(i=0;i<DimSize(sc_Instr, 0);i+=1)
		command = TrimString(sc_Instr[i][0])
		if(strlen(command)>0)
			if(print_cmd==1)
				print ">>> "+command
			endif
			execute/Q/Z command
			if(V_flag!=0)
				print "[ERROR] in sc_openInstrConnections: "+GetErrMessage(V_Flag,2)
			endif
		endif
	endfor
end

// set update speed for ADC (all FD_boxes must have the same speed)

////////////////////////////////
///////// utility functions //// (scu_...)
////////////////////////////////

function scu_unixTime()
	// returns the current unix time in seconds
	return DateTime - date2secs(1970,1,1) - date2secs(-1,-1,-1)
end


function roundNum(number,decimalplace) 
    // to return integers, decimalplace=0
	variable number, decimalplace
	variable multiplier
	multiplier = 10^decimalplace
	return round(number*multiplier)/multiplier
end


Function scu_assertSeparatorType(string list_string, string assert_separator)
    // Validates that the list_string uses the assert_separator exclusively.
    // If it finds an alternative common separator ("," or ";"), it raises an error.
    // This ensures data string consistency, especially in functions that process delimited lists.

    
    // Check if the desired separator is not found in the list_string
    If (strsearch(list_string, assert_separator, 0) < 0)
        // Prepare for potential error messaging
        String buffer
        String calling_func = GetRTStackInfo(2)  // Identifies the function making the call for error context
        
        // Determine the nature of the mismatch based on the asserted separator
        StrSwitch (assert_separator)
            Case ",":
                // If the assert_separator is a comma but a semicolon is found instead
                If (strsearch(list_string, ";", 0) >= 0)
                    // Format and abort with an error message
                    SPrintF buffer, "ERROR[scu_assertSeparatorType]: In function \"%s\" Expected separator = %s     Found separator = ;\r", calling_func, assert_separator
                    Abort buffer
                EndIf
                Break
            
            Case ";":
                // If the assert_separator is a semicolon but a comma is found instead
                If (strsearch(list_string, ",", 0) >= 0)
                    // Format and abort with an error message
                    SPrintF buffer, "ERROR[scu_assertSeparatorType]: In function \"%s\" Expected separator = %s     Found separator = ,\r", calling_func, assert_separator
                    Abort buffer
                EndIf
                Break
            
            Default:
                // If any other separator is asserted but a comma or semicolon is found
                If (strsearch(list_string, ",", 0) >= 0 || strsearch(list_string, ";", 0) >= 0)
                    // Format and abort with a generic error message covering both common separators
                    SPrintF buffer, "ERROR[scu_assertSeparatorType]: In function \"%s\" Expected separator = %s     Found separator = , or ;\r", calling_func, assert_separator
                    Abort buffer
                EndIf
                Break
        EndSwitch      
    EndIf
End

Function/S scu_getChannelNumbers(string channels)
    // This function converts a string of channel identifiers (either names or numbers)
    // into a comma-separated list of channel numbers for FastDAC.
    // It ensures that the channels are properly formatted and exist within the FastDAC configuration.
    
    // Assert that the channels string uses commas as separators
    scu_assertSeparatorType(channels, ",")
    
    // Initialize variables for processing
    String new_channels = "", err_msg
    Variable i = 0
    String ch
    
    // Process for FastDAC channels

        Wave/T fdacvalstr  // Assuming fdacvalstr contains FastDAC channel info
        for(i=0;i<itemsinlist(channels, ",");i+=1)
            // Extract and trim each channel identifier from the list
            ch = stringfromlist(i, channels, ",")
            ch = removeLeadingWhitespace(ch)
            ch = removeTrailingWhiteSpace(ch)
            
            // Check if the channel identifier is not numeric and not empty
            if(numtype(str2num(ch)) != 0 && cmpstr(ch,""))
                // Search for the channel identifier in FastDAC configuration
                duplicate/o/free/t/r=[][3] fdacvalstr fdacnames
                findvalue/RMD=[][3]/TEXT=ch/TXOP=5 fdacnames
                if(V_Value == -1)  // If not found, abort with error
                    sprintf err_msg "ERROR[scu_getChannelNumbers]:No FastDAC channel found with name %s", ch
                    abort err_msg
                else  // If found, use the corresponding channel number
                    ch = fdacvalstr[V_value][0]
                endif
            endif
            // Add the processed channel to the new_channels list
            new_channels = addlistitem(ch, new_channels, ",", INF)
        endfor

    
    // Clean up: Remove the trailing comma from the new_channels string
    if(strlen(new_channels) > 0)
        new_channels = new_channels[0,strlen(new_channels)-1]
    endif
    
    return new_channels
End





