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

//function scfw_update_fdac(action) : ButtonControl
//	string action
//	svar sc_fdackeys
//	wave/t fdacvalstr
//	wave/t old_fdacvalstr
//	nvar fd_ramprate
//
//	scfw_update_all_fdac(option=action)
//end


//function scfw_update_all_fdac([option])
//	// Ramps or updates all FastDac outputs
//	string option // {"fdacramp": ramp all fastdacs to values currently in fdacvalstr, "fdacrampzero": ramp all to zero, "updatefdac": update fdacvalstr from what the dacs are currently at}
//	svar sc_fdackeys
//	wave/t fdacvalstr
//	wave/t old_fdacvalstr
//
//	if (paramisdefault(option))
//		option = "fdacramp"
//	endif
//	
//	
//	// Either ramp fastdacs or update fdacvalstr
//	variable i=0,j=0,output = 0, numDACCh = 8, startCh = 0, viRM = 0
//	string visa_address = "", fdIDname = ""
//	variable numDevices = str2num(stringbykey("numDevices",sc_fdackeys,":",","))
//	for(i=0;i<numDevices;i+=1)
//		numDACCh = scf_getFDInfoFromDeviceNum(i+1, "numDAC")
//		fdIDname = stringByKey("name"+num2str(i+1), sc_fdacKeys, ":", ",")
//		nvar fdID = $fdIDname
//		if(numDACCh > 0)
//			visa_address = stringbykey("visa"+num2istr(i+1),sc_fdackeys,":",",")
//			try
//				strswitch(option)
//					case "fdacramp":
//						for(j=0;j<numDACCh;j+=1)
//							output = str2num(fdacvalstr[startCh+j][1])
//							if(output != str2num(old_fdacvalstr[startCh+j]))
//								rampmultipleFDAC(fdID, num2str(startCh+j), output)
//							endif
//						endfor
//						break
//					case "fdacrampzero":
//						for(j=0;j<numDACCh;j+=1)
//							rampmultipleFDAC(fdID, num2str(startCh+j), 0)
//						endfor
//						break
//					case "updatefdac":
//						variable value
//						for(j=0;j<numDACCh;j+=1)
//							// getfdacOutput(tempname,j)
//							value = getfdacOutput(fdID,j+startCh)
//							scfw_updateFdacValStr(startCh+j, value, update_oldValStr=1)
//						endfor
//						break
//				endswitch
//			catch
//				// reset error code, so VISA connection can be closed!
//				variable err = GetRTError(1)
//				viClose(fdID)
//				
//				// reopen normal instrument connections
//				sc_OpenInstrConnections(0)
//				// silent abort
//				abortonvalue 1,10
//			endtry
//		endif
//		startCh += numDACCh
//	endfor
//end
//



function scfw_update_fadc(action) : ButtonControl
	string action
	svar sc_fdackeys
	wave/t fadcvalstr
	variable i=0

	variable numDevices=1 // = str2num(stringbykey("numDevices",sc_fdackeys,":",","))
	variable numADCCh
	numADCch = 4*numDevices; // 4 is for the 4 ADC channels per FD-box
	variable temp
	for(i=0;i<numADCCh;i+=1)
		temp= getFADCChannelSingle(i)
		fadcvalstr[i][1] = num2str(temp)
	endfor
end



function/S scf_getFDAddress(device_num)
	// Get visa address from device number (has to be it's own function because this returns a string)
	variable device_num
	if(device_num == 0)
		abort "ERROR[scf_getFDVisaAddress]: device_num starts from 1 not 0"
	endif

	svar sc_fdacKeys
	return stringByKey("visa"+num2str(device_num), sc_fdacKeys, ":", ",")
end


//function scf_getFDInfoFromDeviceNum(device_num, info, [str])
//	// Returns the value for selected info of numbered fastDAC device (i.e. 1, 2 etc)
//	// Valid requests ('master', 'name', 'numADC', 'numDAC')
//	variable device_num, str
//	string info
//
//	svar sc_fdacKeys
//
//	if(device_num > scf_getNumFDs())
//		string buffer
//		sprintf buffer,  "ERROR[scf_getFDInfoFromDeviceNum]: Asking for device %d, but only %d devices connected\r", device_num, scf_getNumFDs()
//		abort buffer
//	endif
//
//	string cmd
//	strswitch (info)
//		case "master":
//			cmd = "master"
//			break
//		case "name":
//			cmd = "name"
//			break
//		case "numADC":
//			cmd = "numADCch"
//			break
//		case "numDAC":
//			cmd = "numDACch"
//			break
//		default:
//			abort "ERROR[scf_getFDInfoFromID]: Requested info (" + info + ") not understood"
//			break
//	endswitch
//
//	return str2num(stringByKey(cmd+num2str(device_num), sc_fdacKeys, ":", ","))
//
//end


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
