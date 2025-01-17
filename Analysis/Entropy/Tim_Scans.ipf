////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////// Noise Measurements /////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function standardNoiseMeasurement([instrID, comments, nosave])
	// Run standard noise measurement (i.e. 5x 12s scans with fastdac reading 12kHz)
	// ca_amp_setting = amplification on current amp (i.e. for 1e8 enter 8)
	variable instrID, nosave
	string comments

	if(paramIsDefault(instrID))
		nvar fd
		instrID = fd
	endif
	comments = selectString(paramIsDefault(comments), comments, "")

	variable current_freq = getFADCspeed(instrID)
	setFADCSpeed(instrID, 12195)
	FDSpectrumAnalyzer(12,numAverage=5,comments="noise, spectrum, "+comments, nosave=nosave)
	setFADCSpeed(instrID, current_freq)
end


function QpcStabilitySweeps()
	// 30 mins of slow sweeping down to pinch off and back to depletion to check QPC is stable (taking 90s per sweep, 10 back and forth sweeps)
	nvar fd
	variable pinchoff = -450
	variable depletion = -50

	ScanfastDAC(depletion, pinchoff, "CSQ,CSS", repeats=20, sweeprate=abs(depletion-pinchoff)/90, alternate=1, comments="repeat, alternating, checking stability of CS gates", nosave=0)
	rampmultipleFDAC(fd, "CSQ,CSS", 0)
end



function NoiseOnOffTransition([num_repeats])
	// Assumes that it is starting close to a transition
	// Roughly this does:
	//		CS correction
	// 		Quick centering (with sweepgate, and not very wide)
	// 		1D scan of transition for on transition measurement
	//		Careful centering by fitting and moving to center value
	//		Noise measurement at center of transition
	// 		Move off transition by moving 1000mV away
	// 		Noise measurement off transition
	// 		Move back to transition
	variable num_repeats
	
	num_repeats = (num_repeats == 0) ? 1 : num_repeats
	
	nvar fd
	string CSQ_gate = "CSQ"
	string Sweepgate = "ACC*400"
	variable sweeprate = 100
	variable centering_width = 1000
	string extra_info = "1e9 amplification, 1kHz cutoff, 100uV bias, "
	
	variable sweepgate_start_val = str2num(scf_getDacInfo(sweepgate, "output"))  // Get starting value of sweepgate
	variable i, mid
	// Measure on transition
	for (i=0; i<num_repeats; i++)
		CorrectChargeSensor(fdchannelstr=CSQ_gate, fadcchannel=0, check=0, direction=1)
		mid = CenterOnTransition(gate=sweepgate, width=centering_width, single_only=1)
		
		// 1D scan before noise on transition
		
		ScanFastDAC(mid-centering_width/2, mid+centering_width/2, sweepgate, sweeprate=sweeprate, y_label="Current /nA", comments="transition, Scan before on transition measurment num="+num2istr(i), nosave=0)

		// Careful centering
		wave w = $"cscurrent"
		mid = TransitionCenterFromFit(w)
		if (numtype(mid) == 0)
			rampMultipleFDAC(fd, sweepgate, mid)			
		endif
		
		// Scan on transition
		standardNoiseMeasurement(comments="on transition, "+extra_info+num2str(i))

		// Measure off transition
		rampMultipleFDAC(fd, sweepgate, mid-centering_width)
		standardNoiseMeasurement(comments="off transition, "+extra_info+num2str(i))
		
		// Return to initial position
		rampMultipleFDAC(fd, sweepgate, sweepgate_start_val)
	endfor	
end



///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////// Dot Tuning Stuff /////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function checkPinchOffs(instrID, channels, gate_names, ohmic_names, max_bias, [reset_zero, nosave])
	// Helpful for checking pinch offs
	// reset_zero: Whether to return gates to 0 bias at end of pinch off (defaults to True)
	variable instrID, max_bias, reset_zero, nosave
	string channels, gate_names, ohmic_names

	reset_zero = paramIsDefault(reset_zero) ? 1 : reset_zero
	gate_names = selectString(strlen(gate_names)>0, channels, gate_names)

	string buffer
	sprintf buffer, "Pinch off, Gates=%s, Ohmics=%s", gate_names, ohmic_names
	ScanFastDAC(0, max_bias, channels, sweeprate=300, x_label=gate_names+" /mV", y_label="Current /nA", comments=buffer, nosave=nosave, repeats=2, alternate=1)
	if (reset_zero)
		rampmultiplefdac(instrID, channels, 0)
	endif
end

function checkPinchOffsSlow(instrID, start, fin, channels, numpts, delay, ramprate, current_wave, cutoff_nA, gate_names, ohmic_names, [is_bd])
	/// For testing pinch off (07/2022)
	// Make sure current wave is in nA
	variable instrID, start, fin, numpts, is_bd, delay, ramprate, cutoff_nA
	string channels, current_wave, gate_names, ohmic_names
	
	gate_names = selectString(strlen(gate_names)>0, channels, gate_names)
	
	string comment
	sprintf comment, "Pinch off, Gates=%s, Ohmics=%s", gate_names, ohmic_names

	if (is_bd)
		rampmultiplebd(instrID, channels, 0, ramprate=ramprate)	
		ScanBabyDACUntil(instrID, start, fin, channels, numpts, delay, current_wave, cutoff_nA, ramprate=ramprate, operator="<", y_label="Current /nA", comments=comment)
		rampmultiplebd(instrID, channels, 0, ramprate=ramprate)
	else
		rampmultiplefdac(instrID, channels, 0, ramprate=ramprate)	
		scanfastDacSlow(start, fin, channels, numpts, delay, ramprate, until_checkwave=current_wave, until_stop_val=cutoff_nA, until_operator="<", y_label="Current /nA", comments=comment)
		rampmultiplefdac(instrID, channels, 0, ramprate=ramprate)
	endif
end

function DotTuneAround(x, y, width_x, width_y, channelx, channely, [sweeprate, ramprate_x, numptsy, y_is_bd, fdy_id, csname, fdcs_id, nosave, additional_comments, fadcchannel])
// Goes to x, y. Sets charge sensor to target_current. Scans2D around x, y +- width.
	// Variables:
	// fdy_id: specify if using a fastDAC other than "fd" for the y-axis
	// fdcs_id: specify if the gate for tuning the CS is on a fastDAC other than "fd"
	variable x, y, width_x, width_y, ramprate_x, nosave, y_is_bd, fadcchannel, fdy_id, fdcs_id
	variable sweeprate, numptsy
	string channelx, channely, csname, additional_comments

	sweeprate = paramisdefault(sweeprate) ? 300 : sweeprate
	numptsy = paramisdefault(numptsy) ? 21 : numptsy
	csname = selectstring(paramisdefault(csname), csname, "CSQ")
	nosave = paramisdefault(nosave) ? 0 : nosave
	additional_comments = selectstring(numtype(strlen(additional_comments)) != 0, additional_comments, "")

	nvar fd, bd
	
	variable fdy = paramIsDefault(fdy_id) ? fd : fdy_id
	variable fdcs = paramIsDefault(fdcs_id) ? fd : fdcs_id
	
	
	rampmultiplefdac(fd, channelx, x, ramprate=ramprate_x)
	if (y_is_bd)
		rampmultiplebd(fd, channely, y)
	else
		rampmultiplefdac(fdy, channely, y) // CHANGE FOR FD2 ON Y-AXIS
	endif

	//CorrectChargeSensor(fd=fd, fdchannelstr=csname, fadcID=fd, fadcchannel=fadcchannel, check=0, natarget=natarget, direction=1)
	CorrectChargeSensor(fdchannelstr=csname, fadcchannel=fadcchannel, check=0,  direction=1)
	if (y_is_bd)
		ScanFastDAC2D( x-width_x, x+width_x, channelx, y-width_y, y+width_y, channely, numptsy, bdID = bd, sweeprate=sweeprate, rampratex=ramprate_x, nosave=nosave, comments="Dot Tuning, "+additional_comments)
	else
		ScanFastDAC2D( x-width_x, x+width_x, channelx, y-width_y, y+width_y, channely, numptsy, sweeprate=sweeprate, rampratex=ramprate_x, nosave=nosave, comments="Dot Tuning, "+additional_comments) // CHANGE FOR FD2 ON Y-AXIS
	endif
	wave tempwave = $"cscurrent_2d"
	nvar filenum
	displaydiff(tempwave, filenum=filenum-1, x_label=scu_getDacLabel(scu_getChannelNumbers(channelx, fastdac=1), fastdac=1), y_label=scu_getDacLabel(scu_getChannelNumbers(channely, fastdac=!y_is_bd), fastdac=!y_is_bd))
end


function DotTuneAround2(x, y, width_x, width_y, channelx, channely, [sweeprate, ramprate_x, numptsy, csname, nosave, additional_comments, fadcchannel, natarget, gate_divider, display_diff, delayy, use_AWG])
// Goes to x, y. Sets charge sensor to target_current. Scans2D around x, y +- width.
	variable x, y, width_x, width_y, ramprate_x, nosave, fadcchannel, gate_divider, natarget
	variable sweeprate, numptsy, display_diff, delayy, use_AWG
	string channelx, channely, csname, additional_comments

	sweeprate = paramisdefault(sweeprate) ? 300 : sweeprate
	numptsy = paramisdefault(numptsy) ? 21 : numptsy
	csname = selectstring(paramisdefault(csname), csname, "CSQ2*20")
	nosave = paramisdefault(nosave) ? 0 : nosave
	additional_comments = selectstring(numtype(strlen(additional_comments)) != 0, additional_comments, "")
	gate_divider = paramisdefault(gate_divider) ? 20 : gate_divider
	display_diff = paramisdefault(display_diff) ? 1 : display_diff
	natarget = paramisdefault(natarget) ? 0.99 : natarget
	delayy = ParamIsDefault(delayy) ? 0.05 : delayy
	use_AWG = paramisdefault(use_AWG) ? 0 : use_AWG

	// Set up variables to record CSQ gate value etc	
	wave fdacvalstr
	variable csq_channel_num = str2num(scu_getChannelNumbers(csname, fastdac=1))
	string corners = ""
	
	// First go to middle of scan and get charges sensor roughly right (might want to remove this later)
//	rampmultiplefdac(fd, channelx, x, ramprate=ramprate_x)
//	rampmultiplefdac(fdy, channely, y)
	RampMultipleChannels(channelx, num2str(x))
	RampMultipleChannels(channely, num2str(y))
	CorrectChargeSensor(fdchannelstr=csname, fadcchannel=fadcchannel, check=0, natarget=natarget, direction=1, gate_divider=gate_divider, cutoff_time=15)
	
	// Then go to each corner of the scan and record the CSQ gate value required for CS to be most sensitive
	// Corners ordered (sx|sy, fx|sy, sx|fy, fx|fy)
	make/o/free corner_xs = {x-width_x, x+width_x, x-width_x, x+width_x}
//	make/o/free corner_xs = {x+width_x, x-width_x, x+width_x, x-width_x}
	make/o/free corner_ys = {y-width_y, y-width_y, y+width_y, y+width_y}

	variable i
	for (i=0; i<numpnts(corner_xs);i++)
		RampMultipleChannels(channelx, num2str(corner_xs[i])) 
		RampMultipleChannels(channely, num2str(corner_ys[i]))
		CorrectChargeSensor(fdchannelstr=csname, fadcchannel=fadcchannel, check=0, natarget=natarget, direction=1, gate_divider=gate_divider, cutoff_time=15) //added cutoff time so we don't have to wait while de-bugging
		corners = AddListItem(num2str(fdacvalstr[csq_channel_num][1]), corners, ",", INF) // CSQ gate values
	endfor
	
	///// make parallelogram from corners /////
	corners = make_parallelogram_from_corners(corners)

	ScanFastDAC2D_virtual(x-width_x, x+width_x, channelx, y-width_y, y+width_y, channely, numptsy, corners, csname, sweeprate=sweeprate, rampratex=ramprate_x, nosave=nosave, comments="Dot Tuning, "+additional_comments, delayy=delayy, use_AWG=use_AWG)
////	ScanFastDAC2D_virtual(fd, x+width_x, x-width_x, channelx, y-width_y, y+width_y, channely, numptsy, corners, csname, fdcs_id=fdcs_id, sweeprate=sweeprate, rampratex=ramprate_x, fdyid=fdy, nosave=nosave, comments="Dot Tuning, "+additional_comments)

	wave tempwave = $"cscurrent_2d" // This parameter needs to be the same as in the ScanController ADC Wave Name. 
	nvar filenum
	if (display_diff == 1)
		displaydiff(tempwave, filenum=filenum-1, x_label=scu_getDacLabel(scu_getChannelNumbers(channelx, fastdac=1), fastdac=1), y_label=scu_getDacLabel(scu_getChannelNumbers(channely, fastdac=1), fastdac=1))
	endif
end



function/S make_parallelogram_from_corners(string virtual_corners)
	// Turn any 4 corners into a parallelogram
	// corners are defined in the order [BL, BR, TL, TR]
	// BL: bottom left
	// TR: top right
	// e.g. make_parallelogram_from_corners("0,3,4,5") returns "0.5,2.5,3.5,5.5"
	string corners
	variable c0, c1, c2, c3
	variable new_mid_start, new_mid_end, new_half_width
	
	string new_virtual_corners = ""
	
	variable k
	for (k=0; k < ItemsInList(virtual_corners, ";"); k++)
		corners = StringFromList(k, virtual_corners, ";")
	   	c0 = str2num(StringFromList(0, corners, ","))
   		c1 = str2num(StringFromList(1, corners, ","))
   		c2 = str2num(StringFromList(2, corners, ","))
   		c3 = str2num(StringFromList(3, corners, ","))
   		
		new_half_width = (((c1-c0) + (c3-c2)) / 2) / 2
		new_mid_start = (c0 + c1) / 2
		new_mid_end = (c2 + c3) / 2
		
		c0 = new_mid_start - new_half_width
		c1 = new_mid_start + new_half_width
		c2 = new_mid_end - new_half_width
		c3 = new_mid_end + new_half_width
		
		new_virtual_corners = new_virtual_corners + num2str(c0) + "," + num2str(c1) + ","	 + num2str(c2) + "," + num2str(c3) + ";"							
   	endfor
   		
   	///// remove trailing semicolon... could be dangerous /////
   	new_virtual_corners = new_virtual_corners[0, strlen(new_virtual_corners) - 2]
   		
   	return new_virtual_corners
end


function DotTuneAroundVirtual(x_str, y_str, width_x_str, width_y_str, channelx_str, channely_str, [sweeprate, ramprate_x, numptsy, csname, nosave, additional_comments, fadcchannel, natarget, gate_divider, display_diff, use_AWG, use_only_corners])
// Goes to x, y. Sets charge sensor to target_current. Scans2D around x, y +- width.
	string x_str, y_str, width_x_str, width_y_str, channelx_str, channely_str
	// OPTIONAL	
	variable sweeprate, ramprate_x, numptsy, display_diff, use_AWG, nosave, fadcchannel, gate_divider, natarget, use_only_corners
	string csname, additional_comments

	sweeprate = paramisdefault(sweeprate) ? 300 : sweeprate
	numptsy = paramisdefault(numptsy) ? 21 : numptsy
	csname = selectstring(paramisdefault(csname), csname, "CSQ2*20")
	nosave = paramisdefault(nosave) ? 0 : nosave
	additional_comments = selectstring(numtype(strlen(additional_comments)) != 0, additional_comments, "")
	gate_divider = paramisdefault(gate_divider) ? 20 : gate_divider
	display_diff = paramisdefault(display_diff) ? 1 : display_diff
	natarget = paramisdefault(natarget) ? 0.99 : natarget
	use_AWG = paramisdefault(use_AWG) ? 0 : use_AWG
	use_only_corners = paramisdefault(use_only_corners) ? 0 : use_only_corners

	nvar fd=fd

	// Set up variables to record CSQ gate value etc	
	wave fdacvalstr
	variable csq_channel_num = str2num(scu_getChannelNumbers(csname, fastdac=1))
	string corners = ""
	

	// First go to middle of scan and get charges sensor roughly right (might want to remove this later)
	variable i
	
	for (i=0; i<ItemsInList(channelx_str, ",");i++)
		rampmultipleFDAC(fd, StringFromList(i, channelx_str, ","), str2num(StringFromList(i, x_str, ",")))
	endfor
	
	for (i=0; i<ItemsInList(channely_str, ",");i++)
		rampmultipleFDAC(fd, StringFromList(i, channely_str, ","), str2num(StringFromList(i, y_str, ",")))
	endfor

	CorrectChargeSensor(fdchannelstr=csname,fadcchannel=fadcchannel, check=0, natarget=natarget, direction=1, gate_divider=gate_divider, cutoff_time=15)




  ///// START GOING TO DIFFERENT CORNERS IN SCAN /////
  ///// BOTTOM LEFT OF SCAN /////
  for (i=0; i<ItemsInList(channelx_str, ",");i++)
		rampmultipleFDAC(fd, StringFromList(i, channelx_str, ","), str2num(StringFromList(i, x_str, ",")) - str2num(StringFromList(i, width_x_str, ",")))
  endfor
	
  for (i=0; i<ItemsInList(channely_str, ",");i++)
		rampmultipleFDAC(fd, StringFromList(i, channely_str, ","), str2num(StringFromList(i, y_str, ",")) - str2num(StringFromList(i, width_y_str, ",")))
  endfor
  
  CorrectChargeSensor(fdchannelstr=csname,fadcchannel=fadcchannel, check=0, natarget=natarget, direction=1, gate_divider=gate_divider, cutoff_time=15) //added cutoff time so we don't have to wait while de-bugging
  corners = AddListItem(num2str(fdacvalstr[csq_channel_num][1]), corners, ",", INF)
  
  
  
  ///// BOTTOM RIGHT OF SCAN /////
  for (i=0; i<ItemsInList(channelx_str, ",");i++)
		rampmultipleFDAC(fd, StringFromList(i, channelx_str, ","), str2num(StringFromList(i, x_str, ",")) + str2num(StringFromList(i, width_x_str, ",")))
  endfor
	
  for (i=0; i<ItemsInList(channely_str, ",");i++)
		rampmultipleFDAC(fd, StringFromList(i, channely_str, ","), str2num(StringFromList(i, y_str, ",")) - str2num(StringFromList(i, width_y_str, ",")))
  endfor
  
  CorrectChargeSensor(fdchannelstr=csname, fadcchannel=fadcchannel, check=0, natarget=natarget, direction=1, gate_divider=gate_divider, cutoff_time=15) //added cutoff time so we don't have to wait while de-bugging
  corners = AddListItem(num2str(fdacvalstr[csq_channel_num][1]), corners, ",", INF)
  
  
  
  ///// TOP LEFT OF SCAN /////
  for (i=0; i<ItemsInList(channelx_str, ",");i++)
		rampmultipleFDAC(fd, StringFromList(i, channelx_str, ","), str2num(StringFromList(i, x_str, ",")) - str2num(StringFromList(i, width_x_str, ",")))
  endfor
	
  for (i=0; i<ItemsInList(channely_str, ",");i++)
		rampmultipleFDAC(fd, StringFromList(i, channely_str, ","), str2num(StringFromList(i, y_str, ",")) + str2num(StringFromList(i, width_y_str, ",")))
  endfor
  
  CorrectChargeSensor(fdchannelstr=csname, fadcchannel=fadcchannel, check=0, natarget=natarget, direction=1, gate_divider=gate_divider, cutoff_time=15) //added cutoff time so we don't have to wait while de-bugging
  corners = AddListItem(num2str(fdacvalstr[csq_channel_num][1]), corners, ",", INF)
  
  
  
  ///// TOP RIGHT OF SCAN /////
  for (i=0; i<ItemsInList(channelx_str, ",");i++)
		rampmultipleFDAC(fd, StringFromList(i, channelx_str, ","), str2num(StringFromList(i, x_str, ",")) + str2num(StringFromList(i, width_x_str, ",")))
  endfor
	
  for (i=0; i<ItemsInList(channely_str, ",");i++)
		rampmultipleFDAC(fd, StringFromList(i, channely_str, ","), str2num(StringFromList(i, y_str, ",")) + str2num(StringFromList(i, width_y_str, ",")))
  endfor
  
  CorrectChargeSensor(fdchannelstr=csname, fadcchannel=fadcchannel, check=0, natarget=natarget, direction=1, gate_divider=gate_divider, cutoff_time=15) //added cutoff time so we don't have to wait while de-bugging
  corners = AddListItem(num2str(fdacvalstr[csq_channel_num][1]), corners, ",", INF)
  
  
  
  
  ///// CREATING STARTS AND FINS /////  
  String starts_x = ""
  String fins_x = ""
  String starts_y = ""
  String fins_y = ""
  
  /// X ///
  for (i=0; i<ItemsInList(channelx_str, ",");i++)
      starts_x = starts_x + num2str(str2num(StringFromList(i, x_str, ",")) - str2num(StringFromList(i, width_x_str, ","))) + ","
      fins_x = fins_x + num2str(str2num(StringFromList(i, x_str, ",")) + str2num(StringFromList(i, width_x_str, ","))) + ","     
  endfor
  starts_x = starts_x[0, strlen(starts_x) - 2]
  fins_x = fins_x[0, strlen(fins_x) - 2]
  
  /// Y ///
  for (i=0; i<ItemsInList(channely_str, ",");i++)
      starts_y = starts_y + num2str(str2num(StringFromList(i, y_str, ",")) - str2num(StringFromList(i, width_y_str, ","))) + ","
      fins_y = fins_y + num2str(str2num(StringFromList(i, y_str, ",")) + str2num(StringFromList(i, width_y_str, ","))) + ","     
  endfor
  starts_y = starts_y[0, strlen(starts_y) - 2]
  fins_y = fins_y[0, strlen(fins_y) - 2]
  
  	
  	/// DOING VIRTUAL DOT TUNE ///
	ScanFastDAC2D_virtual( 0, 0, channelx_str, 0, 0, channely_str, numptsy, corners, csname, sweeprate=sweeprate, rampratex=ramprate_x, nosave=nosave, comments="Dot Tuning Virtual, "+additional_comments, startxs=starts_x, finxs=fins_x, startys=starts_y, finys=fins_y, use_AWG=use_AWG)

	wave tempwave = $"cscurrent_2d" // This parameter needs to be the same as in the ScanController ADC Wave Name. 
	nvar filenum
	if (display_diff == 1)
		displaydiff(tempwave, filenum=filenum-1, x_label=channelx_str, y_label=channely_str)
	endif
end


function ScanFastDAC2D_virtual(startx, finx, channelsx, starty, finy, channelsy, numptsy, virtual_corners, virtual_gates, [numpts, sweeprate, bdID, rampratex, rampratey, delayy, startxs, finxs, startys, finys, comments, nosave, use_AWG, use_only_corners, interlaced_channels, interlaced_setpoints])
	// 2D Scan for FastDAC only OR FastDAC on fast axis and BabyDAC on slow axis
	// Note: Must provide numptsx OR sweeprate in optional parameters instead
	// Note: To ramp with babyDAC on slow axis provide the BabyDAC variable in bdID
	// Note: channels should be a comma-separated string ex: "0,4,5"
	// Note: Virtual corner gates MUST be on the fast axis (since they are swept during the scan)
	variable startx, finx, starty, finy, numptsy, numpts, sweeprate, bdID, rampratex, rampratey, delayy, nosave, use_AWG, use_only_corners
	string channelsx, channelsy, comments, startxs, finxs, startys, finys, interlaced_channels, interlaced_setpoints
	string virtual_corners  // , separated list of 4 corner values for each virtual gate. ; separated for multiple virtual gates -- Corners should be specified as a single value for each of "StartX|StartY, FinX|StartY, StartX|FinY, FinX|FinY"
	string virtual_gates  // , separated list of virtual gates (each needs a set of virtual_corners)

	// Set defaults
	delayy = ParamIsDefault(delayy) ? 0.05 : delayy
	comments = selectstring(paramisdefault(comments), comments, "")
	startxs = selectstring(paramisdefault(startxs), startxs, "")
	finxs = selectstring(paramisdefault(finxs), finxs, "")
	startys = selectstring(paramisdefault(startys), startys, "")
	finys = selectstring(paramisdefault(finys), finys, "")
	use_only_corners = paramisdefault(use_only_corners) ? 0 : use_only_corners
	interlaced_channels = selectString(paramisdefault(interlaced_channels), interlaced_channels, "")
	interlaced_setpoints = selectString(paramisdefault(interlaced_setpoints), interlaced_setpoints, "")
	variable use_bd = paramisdefault(bdid) ? 0 : 1 		// Whether using both FD and BD or just FD
	
	
	///// If using virtual sweeps only /////
	///// WARNING DANGEROUS NEED TO PROPERLY DO CHECKS HERE /////
	string corners, virtual_gate
   	variable c0, c1, c2, c3 
   	
	if (use_only_corners == 1)
		corners = StringFromList(0, virtual_corners, ";")
	   	c0 = str2num(StringFromList(0, corners, ","))
   		c1 = str2num(StringFromList(1, corners, ","))
   		c2 = str2num(StringFromList(2, corners, ","))
   		c3 = str2num(StringFromList(3, corners, ","))
	   	
	   	// NOTE: These values are only for plotting if use_only_corners == 1
	   	// Choosing to display extrema
		startx = min(c0, c2)
		finx = max(c1, c3)
		starty = min(c0, c1)
		finy = max(c2, c3)
		
		// making it clear the virtual gates are getting swept
		channelsx = virtual_gates
		channelsy = virtual_gates
	endif

	
	///// Reconnect instruments /////
	sc_openinstrconnections(0)


	////////////////// Add some info to the comments otherwise virtual gate info not stored in HDF
	// TODO: Improve how this info is stored in HDF (probably requires adding something to ScanVars and then modifying EndScan)
	sprintf comments, "%s, virtual_sweep, [virtual_gates=%s, virtual_corners=%s]", comments, virtual_gates, virtual_corners

	struct ScanVars S
 	if (use_bd == 1)  // Using babydacs as second instrument
		
		initScanVarsFD2(S, startx, finx, channelsx=channelsx, rampratex=rampratex, numptsx=numpts, sweeprate=sweeprate, numptsy=numptsy, delayy=delayy,\
		   				 rampratey=rampratey, startxs=startxs, finxs=finxs, interlaced_channels=interlaced_channels, interlaced_setpoints=interlaced_setpoints,\
		   				 comments=comments)

		S.instrIDy = bdID
		S.channelsy = scu_getChannelNumbers(channelsy, fastdac=0)
		S.y_label = scu_getDacLabel(S.channelsy, fastdac=0)
		scv_setSetpoints(S, S.channelsx, S.startx, S.finx, S.channelsy, starty, finy, S.startxs, S.finxs, startys, finys)
	
	else  				// Using fastdacs as second instrument

		initScanVarsFD2(S, startx, finx, channelsx=channelsx, rampratex=rampratex, numptsx=numpts, sweeprate=sweeprate, numptsy=numptsy, delayy=delayy,\
		   				 starty=starty, finy=finy, channelsy=channelsy, rampratey=rampratey, startxs=startxs, finxs=finxs, startys=startys, finys=finys,\
		   				 interlaced_channels=interlaced_channels, interlaced_setpoints=interlaced_setpoints, comments=comments, x_only = 0)

		s.is2d = 1		   						
		S.starty = starty
		S.finy = finy
		scv_setSetpoints(S, S.channelsx, S.startx, S.finx, S.channelsy, starty, finy, S.startxs, S.finxs, startys, finys)
		
	endif
      
   ///// Check software limits and ramprate limits and that ADCs/DACs are on same FastDAC ///
   // NOTE: No checks of the virtual gates done here
   if(use_bd == 1)
		PreScanChecksBD(S, y_only=1)
   endif
   
   PreScanChecksFD(S, same_device = 0) 
   	
   	
   	// sets master/slave between the devices that are used.
	set_master_slave(S)
	
	
   	///// Check virtual gates /////
   	variable k
   	for (k=0; k<ItemsInList(virtual_gates, ","); k++)
   		virtual_gate = scu_getChannelNumbers(StringFromList(k, virtual_gates, ","), fastdac=1)
   		corners = StringFromList(k, virtual_corners, ";")
   		if (ItemsInList(corners, ",") != 4)
   			abort "Must specify all 4 corner values for each virtual gate (StartX/Y, FinX/StartY, StartX/FinY, FinX/FinY)"
   		endif
   		c0 = str2num(StringFromList(0, corners, ","))
   		c1 = str2num(StringFromList(1, corners, ","))
   		c2 = str2num(StringFromList(2, corners, ","))
   		c3 = str2num(StringFromList(3, corners, ","))
   		scc_checkLimsSingleFD(virtual_gate, c0, c1)
   		scc_checkLimsSingleFD(virtual_gate, c2, c3) 
   		// NOTE: Not checking the sweeprate of virtual gates 		
   	endfor

   	
  	///// If using AWG then get that now and check it /////
	struct AWGVars AWG
	if(use_AWG)	
		fd_getGlobalAWG(AWG)
		CheckAWG(AWG, S)  // Note: sets S.numptsx here and AWG.lims_checked = 1
	endif
	SetAWG(AWG, use_AWG)
   
   
   ///// Ramp to start without checks /////
   if(use_bd == 1)
	   RampStartFD(S, x_only=1, ignore_lims=1)
	   RampStartBD(S, y_only=1, ignore_lims=1)
   	else
   	   RampStartFD(S, ignore_lims=1)
   	endif
   	

	///// Ramp Virtual gates to start /////
	
	for (k=0; k<ItemsInList(virtual_gates, ","); k++)
		virtual_gate = scu_getChannelNumbers(StringFromList(k, virtual_gates, ","), fastdac=1)
		string IDname = scc_getDeviceIDs(channels = virtual_gate)
		IDname = removeseperator(IDname, ";")
		nvar fdID = $IDname
	   	corners = StringFromList(k, virtual_corners, ";")
	   	c0 = str2num(StringFromList(0, corners, ","))
	   	rampmultipleChannels(virtual_gate, num2str(c0), ignore_lims=1)
	endfor

   	
   	///// Let gates settle /////
	sc_sleep(S.delayy)


	///// Initialize waves and graphs /////
	initializeScan(S)


	///// Main measurement loop /////
	variable i=0, j=0
	variable setpointy, sy, fy
	string chy
	
	variable new_start, new_fin
	string original_channelsx = S.channelsx, original_startxs = S.startxs, original_finxs = S.finxs
	string original_daclistids = S.dacListIDs

	for(i=0; i < S.numptsy; i++)
	
	
		///// Add virtual gates into ScanVars /////
		if (use_only_corners == 1) // if only using corners - remove other gates
			S.channelsx = ""
			S.startxs = ""
			S.finxs = ""
			S.dacListIDs = ""
		else
			S.channelsx = original_channelsx
			S.startxs = original_startxs
			S.finxs = original_finxs
			S.dacListIDs = original_daclistids

		endif
		
		
		///// Calculate new Virtual gates start/end /////
		for (k=0; k < ItemsInList(virtual_gates, ","); k++)
			virtual_gate = scu_getChannelNumbers(StringFromList(k, virtual_gates, ","), fastdac=1)
   			corners = StringFromList(k, virtual_corners, ";")
		   	c0 = str2num(StringFromList(0, corners, ","))
	   		c1 = str2num(StringFromList(1, corners, ","))
	   		c2 = str2num(StringFromList(2, corners, ","))
	   		c3 = str2num(StringFromList(3, corners, ","))
	   		
	   		new_start = c0 + (c2-c0) * i / (S.numptsy-1)
			new_fin = c1 + (c3-c1) * i / (S.numptsy-1)
			
			S.channelsx = AddListItem(virtual_gate, S.channelsx, ",", INF)
			S.startxs = AddListItem(num2str(new_start), S.startxs, ",", INF)			
			S.finxs = AddListItem(num2str(new_fin), S.finxs, ",", INF)	
			S.dacListIDs = AddListItem(stringfromlist(0, scc_getDeviceIDs(channels=virtual_gate)), S.dacListIDs, ";", INF) // add virtual_gate device ID to S.dacListIDs (use stringfromlist to strip semicolon)
   		endfor
   		
   		
   		///// Remove the commas Igor puts at the end of lists /////
   		S.channelsx = S.channelsx[0, strlen(S.channelsx) - 2]  
   		S.startxs = S.startxs[0, strlen(S.startxs) - 2]
   		S.finxs = S.finxs[0, strlen(S.finxs) - 2]
   		
   		scv_setSetpoints(S, S.channelsx, S.startx, S.finx, S.channelsy, starty, finy, S.startxs, S.finxs, startys, finys)
   		
   		///// Loop for interlaced scans ///// 
		if (S.interlaced_y_flag)
			Ramp_interlaced_channels(S, mod(i, S.interlaced_num_setpoints))
			Set_AWG_state(S, AWG, mod(i, S.interlaced_num_setpoints))
			///// Ramp slow axis only for first of interlaced setpoints /////
			if (mod(i, S.interlaced_num_setpoints) == 0)
				rampToNextSetpoint(S, 0, outer_index=i, y_only=1, fastdac=!use_bd, ignore_lims=1)
			endif
		else
			///// Ramp slow axis /////
			rampToNextSetpoint(S, 0, outer_index=i, y_only=1, fastdac=!use_bd, ignore_lims=1)
		endif
 
		
		///// Ramp fast axis to start /////
		rampToNextSetpoint(S, 0, fastdac=1, ignore_lims=1)


		///// Let gates settle /////
		sc_sleep(S.delayy)
		
		
		///// RECORD fast axis /////
		scfd_RecordValues(S, i, AWG_list=AWG)
		
	endfor
	
	///// Save by default /////
	if (nosave == 0)
		EndScan(S=S)
  	else
  		dowindow /k SweepControl
	endif

end



function ScanFastDacSlow_Interlaced(instrID, start, fin, channels, numpts, delay, ramprate, [starts, fins, y_label, repeats, alternate, delayy, until_checkwave, until_stop_val, until_operator, comments, nosave, interlace_channel, interlaced_setpoints]) //Units: mV
	//////////////// UPDATED FOR MASTER/SLAVE But NOT TESTED ////////////////////////////////////////////////////
	
	
	// sweep one or more FastDAC channels but in the ScanController way (not ScanControllerFastdac). I.e. ramp, measure, ramp, measure...
	// channels should be a comma-separated string ex: "0, 4, 5"
	// Allows for Interlaced measurement (where interlaced_channels step through interlaced_setpoints throughout the scan)
	// Note: DACs do step between Interlace measurements (i.e. Interlaced measurements are NOT at exactly the same DAC settings)
	variable instrID, start, fin, numpts, delay, ramprate, nosave, until_stop_val, repeats, alternate, delayy
	string channels, y_label, comments, until_operator, until_checkwave, interlace_channel
	wave interlaced_setpoints
	string starts, fins // For different start/finish points for each channel (must match length of channels if used)

	// Reconnect instruments
	sc_openinstrconnections(0)

	// Set defaults
	comments = selectstring(paramisdefault(comments), comments, "")
	y_label = selectstring(paramisdefault(y_label), y_label, "")
	starts = selectstring(paramisdefault(starts), starts, "")
	fins = selectstring(paramisdefault(fins), fins, "")
	until_operator = selectstring(paramisdefault(until_operator), until_operator, "not_set")
	delayy = ParamIsDefault(delayy) ? 5*delay : delayy
	
	variable a
	if (stringmatch(until_operator, "not_set") == 1)
		a = 0
	else
		if (paramisdefault(until_checkwave) || paramisdefault(until_stop_val))
			abort "If scanning until condition met, you must set a checkwave and stop_val"
		else
			wave cw = $until_checkwave
		endif
		
		if ( stringmatch(until_operator, "<")==1 )
			a = 1
		elseif ( stringmatch(until_operator, ">")==1 )
			a = -1
		else
			abort "Choose a valid operator (<, >)"
		endif
	endif
	

	// Initialize ScanVars
	struct ScanVars S  // Note, more like a BD scan if going slow
	initScanVarsFD2(S, start, fin, channelsx=channels, numptsx=numpts, delayx=delay, rampratex=ramprate, startxs = starts, finxs = fins, comments=comments, y_label=y_label,\
	 		starty=1, finy=repeats,  numptsy=repeats, alternate=alternate, delayy=delay)
	 		   
	if (s.is2d && strlen(S.y_label) == 0)
		S.y_label = "Repeats"
	endif	 		
	S.using_fastdac = 0 // Explicitly showing that this is not a normal fastDac scan
	S.duration = numpts*max(0.05, delay) // At least 50ms per point is a good estimate 
	S.sweeprate = abs((fin-start)/S.duration) // Better estimate of sweeprate (Not really valid for a slow scan)

	// Check limits (not as much to check when using FastDAC slow)
	scc_checkLimsFD(S)
	S.lims_checked = 1

	// Ramp to start without checks because checked above
	RampStartFD(S, ignore_lims=1)

	// Let gates settle 
	sc_sleep(S.delayy)

	// Make Waves and Display etc
	InitializeScan(S)

	// Main measurement loop
	variable i=0, j=0
	variable d=1
	for (j=0; j<S.numptsy; j++)
		S.direction = d  // Will determine direction of scan in fd_Record_Values

		// Ramp to start of fast axis
		RampStartFD(S, ignore_lims=1, x_only=1)
		sc_sleep(S.delayy)
		i = 0
		do
			rampToNextSetpoint(S, i, fastdac=1, ignore_lims=1)  // Ramp x to next setpoint
			if (!paramisdefault(interlace_channel) && !paramisdefault(interlaced_setpoints))
				int k
				interlace_channel = scu_getChannelNumbers(interlace_channel, fastdac=1)
				string interlace_IDs = scc_getDeviceIDs(channels = interlace_channel)
				for(k=0;k<itemsinlist(interlace_channel, ",");k++)
							string IDname = stringfromlist(i, interlace_IDs)
							nvar fdID = $IDname
					rampmultiplefdac(fdID, stringfromlist(i, interlace_channel, ","), interlaced_setpoints[mod(i, numpnts(interlaced_setpoints))])			
				endfor			
//printf "DEBUG: Ramping channel %s to %.1f\r", interlace_channel, interlaced_setpoints[mod(i, numpnts(interlaced_setpoints))]							
			endif
			sc_sleep(S.delayx)
			if (s.is2d)
				RecordValues(S, j, i)
			else
				RecordValues(S, i, 0)
			endif
			if (a!=0)  // If running scan until condition is met
				if (a*cw[i] - until_stop_val < 0)
					break
				endif
			endif
			i+=1
		while (i<S.numptsx)
		
		if (alternate!=0) // If want to alternate scan scandirection for next row
			d = d*-1
		endif
	endfor
	

	// Save by default
	if (nosave == 0)
		EndScan(S=S)
	else
		dowindow /k SweepControl
	endif
end


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////// Generally Useful Scan Functions ////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

function ScanAlongTransition(step_gate, step_size, step_range, center_gate, sweep_gate, sweeprate, repeats, width, [center_step_ratio, centering_width, center_sweep_gate, scan_type, correct_cs_gate, sweep_gate_start, load_datnum, hqpc_bias, ramprate, num, correction_gate, corr_step_ratio, step_gate_isbd, mid, virtual_gate, natarget, additional_Setup, additional_comments])
	// Scan at many positions along a transition, centering on transition for each scan along the way.
	// Rather than doing a true scan along transition, this just takes a series of short repeat measurements in small steps. Will make LOTS of dats, but keeps things a lot simpler
	//
	// step_gate: Gate to step along transition with. These always do fixed steps, center_gate is used to center back on transition
	// step_size: mV to step between each repeat scan
	// step_range: How far to keep stepping in step_gate (i.e. 50 would mean 10 steps for 5mV step size)
	// center_gate: Gate to use for centering on transition
	// sweep_gate: Gate to sweep for scan (i.e. plunger or accumulation)
	// center_step_ratio: Roughly the amount center_gate needs to step to counteract step_gates (will default to 0)
	// centering_width: How wide to scan for CenterOnTransition
	// center_sweep_gate: Whether to also center the sweep gate, or just sweep around 0
	// width: Width of scan around center of transition in sweep_gate (actually sweeps + and - width)
	// correct_cs_gate: Gate to use for correcting the Charge Sensor
	// sweep_gate_start: Start point for sweepgate, useful when loading from hdf
	// hqpc_bias: mV to apply to current bias resistor for square entropy heating
	// num: Number of times to repeat measurement at each step
	// correction_gate: Secondary stepping gate for something like a constant gamma scan
	// corr_step_ratio: Proportion of step gate potential to apply to the correction gate each step
	// step_gate_isbd: If step gate is on bd, set = 1
	// mid: center value for sweepgate
	// natarget: Target nA for current amp
	// additional_setup: set to 1 to call additionalSetupAfterLoadHDF()  (i.e. useful if LoadfromHDF gets almost all the gates right, and then there a few minor tweaks after that).
	variable step_size, step_range, center_step_ratio, sweeprate, repeats, center_sweep_gate, width, sweep_gate_start, load_datnum, centering_width, hqpc_bias, ramprate, num, corr_step_ratio, step_gate_isbd, mid, virtual_gate, natarget, additional_setup
	string step_gate, center_gate, sweep_gate, correct_cs_gate, scan_type, correction_gate, additional_comments

	center_step_ratio = paramisdefault(center_step_ratio) ? 0 : center_step_ratio
	corr_step_ratio = paramisdefault(corr_step_ratio) ? 0 : corr_step_ratio
	hqpc_bias = paramisdefault(hqpc_bias) ? 20 : hqpc_bias
	centering_width = paramIsDefault(centering_width) ? 20 : centering_width
	scan_type = selectstring(paramIsDefault(scan_type), scan_type, "transition")
	correct_cs_gate = selectstring(paramIsDefault(correct_cs_gate), correct_cs_gate, "CSQ")
	ramprate = paramisDefault(ramprate) ? 10*sweeprate : ramprate
	num =  paramisDefault(num) ? 1 : num
	step_gate_isbd =  paramisDefault(step_gate_isbd) ? 0 : step_gate_isbd
	variable step_gate_isfd = !step_gate_isbd
	mid =  paramisDefault(mid) ? 0 : mid
	natarget = paramisdefault(natarget) ? 1.5 : natarget
	
	variable center_limit = -0  // Above this value in step gate, don't try to center (i.e. gamma broadened)
	variable correct_cs_fadcchannel = 1
	variable correct_cs_gate_divider = 19.7

	nvar fd, bd

	if (!paramIsDefault(load_datnum))
		loadFromHDF(load_datnum, no_check=1)
		if (additional_setup)
			additionalSetupAfterLoadHDF()
		endif
		if (!paramisdefault(sweep_gate_start))
			rampmultiplefdac(fd, sweep_gate, sweep_gate_start)
		endif
	endif

	wave/T fdacvalstr
	wave/T dacvalstr

	variable sg_val, cg_val, corrg_val, csq_val
	variable total_scan_range = 0  // To keep track of how far has been scanned
	variable i = 0

	do
		// Get DAC val of step_gate
		if (step_gate_isfd)
			sg_val = str2num(fdacvalstr[str2num(scu_getChannelNumbers(step_gate, fastdac=1))][1])
		else
			sg_val = str2num(dacvalstr[str2num(scu_getChannelNumbers(step_gate, fastdac=0))][1])
		endif
		
		// Get DAC val of centering_gate
		if (cmpstr(center_gate, sweep_gate) == 0)
			cg_val = mid
		else
			cg_val = str2num(fdacvalstr[str2num(scu_getChannelNumbers(center_gate, fastdac=1))][1]) //get DAC val of centering_gate
		endif
		
		// Get DAC val of correction_gate
		if (!paramIsDefault(correction_gate))
			corrg_val = str2num(fdacvalstr[str2num(scu_getChannelNumbers(correction_gate, fastdac=1))][1]) //get DAC val of correction_gate
		endif

		// Reset sweepgate
		RampMultiplefdac(fd, sweep_gate, mid)

		// Ramp step_gate (and correction_gate) to next value
		if (i != 0)
			if (step_gate_isfd)
				RampMultiplefdac(fd, step_gate, sg_val+step_size)
			else
				RampMultiplebd(bd, step_gate, sg_val+step_size)
			endif
			cg_val += step_size*center_step_ratio
			RampMultiplefdac(fd, center_gate, cg_val)
			total_scan_range += step_size
			if (!paramIsDefault(correction_gate))
				RampMultiplefdac(fd, correction_gate, corrg_val+step_size*corr_step_ratio)
			endif
			sg_val = sg_val+step_size
		endif
		
		// Center and correct charge sensor
		if (cmpstr(center_gate, sweep_gate) != 0)
			RampMultiplefdac(fd, sweep_gate, mid-50)
		else
			mid = cg_val
		endif
		
		CorrectChargeSensor(fdchannelstr=correct_cs_gate, fadcchannel=correct_cs_fadcchannel, check=0, direction=1, natarget=natarget, gate_divider=correct_cs_gate_divider)
		RampMultiplefdac(fd, sweep_gate, mid)
		if(sg_val < center_limit)
			cg_val = CenterOnTransition(gate=center_gate, width=centering_width, single_only=1)
			if (cmpstr(center_gate, sweep_gate) != 0)
				RampMultiplefdac(fd, sweep_gate, mid-200)
				CorrectChargeSensor(fdchannelstr=correct_cs_gate, fadcchannel=correct_cs_fadcchannel, check=0, direction=1, natarget=natarget, gate_divider=correct_cs_gate_divider)
				RampMultiplefdac(fd, sweep_gate, mid)
				cg_val = CenterOnTransition(gate=center_gate, width=centering_width, single_only=1)
			else
				CorrectChargeSensor(fdchannelstr=correct_cs_gate, fadcchannel=correct_cs_fadcchannel, check=0, direction=1, natarget=natarget, gate_divider=correct_cs_gate_divider)
				cg_val = CenterOnTransition(gate=center_gate, width=centering_width, single_only=1)
			endif
		endif
		
		if (cmpstr(center_gate, sweep_gate) == 0)  // If center gate is also sweep gate, then need to get new mid cg_val
			mid = cg_val
		endif
		
		if (center_sweep_gate)
			mid = CenterOnTransition(gate=sweep_gate, width=width, single_only=1)
		endif

		RampMultiplefdac(fd, sweep_gate, mid-200)
		CorrectChargeSensor(fdchannelstr=correct_cs_gate, fadcchannel=correct_cs_fadcchannel, check=0, direction=1, natarget=natarget, gate_divider=correct_cs_gate_divider)

		string virtual_mids
		strswitch (scan_type)
			case "center_test":
				ScanFastDAC( -1000, 1000, "ACC*400", sweeprate=10000, nosave=1)
				rampmultiplefdac(fd, "ACC*400", 0)
				break
			case "transition":
				ScanTransition(sweep_gate=sweep_gate, sweeprate=sweeprate, width=width, ramprate=ramprate, repeats=repeats, center_first=center_sweep_gate, mid=mid, alternate=1, additional_comments=additional_comments)
				break
			case "noise+transition":
				NoiseOnOffTransition(num_repeats=1)
				ScanTransition(sweeprate=sweeprate, width=width, ramprate=ramprate, repeats=repeats, center_first=center_sweep_gate, mid=mid, alternate=1)
				break
			case "noise":
				NoiseOnOffTransition(num_repeats=1)			
				break
			case "dcbias_transition":
				rampmultipleFDAC(fd, "OHC(10M)", hqpc_bias)
				rampmultipleFDAC(fd, "OHV*1000", hqpc_bias*-1.478)
				ScanTransition(sweeprate=sweeprate, width=width, ramprate=ramprate, repeats=repeats, center_first=center_sweep_gate, mid=mid, additional_comments="dcbias="+num2str(hqpc_bias))
				break
			case "entropy":
				ScanEntropyRepeat(center_first=0, balance_multiplier=1, width=width, hqpc_bias=hqpc_bias, additional_comments=", scan along transition, scan:"+num2str(i), sweeprate=sweeprate, repeats=repeats, num=num, center=mid)
				break
			case "noise+entropy":
				NoiseOnOffTransition(num_repeats=1)
				ScanEntropyRepeat(center_first=0, balance_multiplier=1, width=width, hqpc_bias=hqpc_bias, additional_comments=", scan along transition, scan:"+num2str(i), sweeprate=sweeprate, repeats=repeats, num=num, center=mid)
				break
			case "entropy+transition":
				ScanEntropyRepeat(center_first=0, balance_multiplier=1, width=width, hqpc_bias=hqpc_bias, additional_comments=", scan along transition, scan:"+num2str(i), sweeprate=sweeprate, repeats=repeats, num=num, center=mid)
				ScanTransition(sweeprate=sweeprate*50, width=width*1.5, repeats=repeats*5, center_first=0, additional_comments=", scan along transition, scan:"+num2str(i), mid=mid)
				break
			case "csq only":
				RampMultiplefdac(fd, "ACC*1000", -10000)
				csq_val = str2num(fdacvalstr[str2num(scu_getChannelNumbers("CSQ", fastdac=1))][1])
				ScanFastDAC( csq_val-50, csq_val+50, "CSQ", sweeprate=100, nosave=0, comments="charge sensor trace")
				RampMultiplefdac(fd, "ACC*1000", 0)
				RampMultiplefdac(fd, "CSQ", csq_val)
				break
			default:
				abort scan_type + " not recognized"
		endswitch
		i++

	while (total_scan_range + step_size <= step_range)

end



function TimStepTempScanSomething()
	nvar fd
	svar ls370

	make/o targettemps =  {300, 275, 250, 225, 200, 175, 150, 125, 100, 75, 50, 40, 30, 20}
	make/o targettemps =  {300, 250, 200, 150, 100, 75, 50, 35}
//   make/o targettemps =  {50, 100, 150, 200, 250, 300}
	setLS370exclusivereader(ls370,"mc")

   // Scan at current temp
//	ScanTransition(sweeprate=width/5, width=width, repeats=100, center_first=1, center_gate="ACC*2", center_width=10, sweep_gate="ACC*400", csqpc_gate="CSQ", additional_comments="Temp = " + num2str(targettemps[i]) + " mK")
   ScanTransition(sweeprate=500, width=1000, repeats=2, center_first=1, center_gate="P*2", center_width=20, sweep_gate="P*200",alternate=1)
    
	variable width
	variable i=0
	do
		setLS370temp(ls370,targettemps[i])
		asleep(2.0)
		WaitTillTempStable(ls370, targettemps[i], 5, 20, 0.10)
		asleep(60.0)
		print "MEASURE AT: "+num2str(targettemps[i])+"mK"

		// Scan Goes here
		width = max(100, 4*targettemps[i])
		ScanTransition(sweeprate=width/5, width=width, repeats=100, center_first=1, center_gate="ACC*2", center_width=10, sweep_gate="ACC*400", csqpc_gate="CSQ", additional_comments="Temp = " + num2str(targettemps[i]) + " mK")
		//////////////////////
		i+=1
	while ( i<numpnts(targettemps) )

	// kill temperature control


//	setLS370heaterOff(ls370)
	setLS370temp(ls370,10)
	resetLS370exclusivereader(ls370)
	asleep(60.0*60)

	// Base T Scan goes here
	width = 100
	ScanTransition(sweeprate=width/5, width=width, repeats=100, center_first=1, center_gate="ACC*2", center_width=10, sweep_gate="ACC*400", csqpc_gate="CSQ", additional_comments="Temp = 10 mK")
	/////////////////////////////////
end


function ScanEntropyRepeat([num, center_first, balance_multiplier, width, hqpc_bias, additional_comments, repeat_multiplier, freq, sweeprate, repeats, cs_target, center, cycles])
	variable num, center_first, balance_multiplier, width, hqpc_bias, repeat_multiplier, freq, sweeprate, repeats, cs_target, center, cycles
	string additional_comments
	nvar fd

	num = paramisdefault(num) ? 										INF : num
	center_first = paramisdefault(center_first) ? 				0 : center_first
	balance_multiplier = paramisdefault(balance_multiplier) ? 	1 : balance_multiplier
	hqpc_bias = paramisdefault(hqpc_bias) ? 						20 : hqpc_bias
	repeat_multiplier = paramisDefault(repeat_multiplier) ? 	1 : repeat_multiplier
	sweeprate = paramisdefault(sweeprate) ? 						100 : sweeprate
	freq = paramisdefault(freq) ? 									12.5 : freq
	center = paramisdefault(center) ? 								0 : center
	cycles = paramisdefault(cycles) ? 								1 : cycles


	string sweepgate = "ACC*400"
	variable sweepgate_center_width = 500
	string centergate = "ACC*2"
	variable center_width = 30

	nvar sc_ResampleFreqCheckfadc
	variable resample_state = sc_ResampleFreqCheckfadc
	sc_ResampleFreqCheckfadc = 0  // Resampling in entropy measurements screws things up at the moment so turn it off (2021-12-02)

	variable nosave = 0

	variable width1 = paramisdefault(width) ? 1000 : width
	
	string comments = "transition, square entropy, repeat, "
	if (!paramisdefault(additional_comments))
		sprintf comments, "%s%s, ", comments, additional_comments
	endif

	variable splus = hqpc_bias, sminus=-hqpc_bias
	SetupEntropySquareWaves(freq=freq, cycles=cycles, hqpc_plus=splus, hqpc_minus=sminus, balance_multiplier=balance_multiplier)

//	variable cplus=-splus*0.031 * balance_multiplier, cminus=-sminus*0.031 * balance_multiplier
//	SetupEntropySquareWaves_unequal(freq=freq, hqpc_plus=splus, hqpc_minus=sminus, balance_multiplier=balance_multiplier)

	variable mid, r
	if (center_first)
		rampmultiplefdac(fd, sweepgate, center)
		centerontransition(gate=centergate, width=center_width)
		rampmultiplefdac(fd, sweepgate, center-200)
		if (!paramisdefault(cs_target))
			CorrectChargeSensor(fdchannelstr="CSQ", fadcchannel=0, check=0, direction=1, natarget=cs_target)
		else
			CorrectChargeSensor(fdchannelstr="CSQ", fadcchannel=0, check=0, direction=1)
		endif
		rampmultiplefdac(fd, sweepgate, center)
		mid = centerontransition(gate=sweepgate, width=sweepgate_center_width, single_only=1)
		if (numtype(mid) == 2)
			mid = center
		endif
	else
		mid = center
	endif

	variable i=0
	string virtual_starts_ends
	do
		if(paramisdefault(num))
			printf "Starting scan %d of \u221E\r", i+1
		else
			printf "Starting scan %d of %d\r", i+1, num
		endif
		ScanFastDAC( mid-width1, mid+width1, sweepgate, repeats=repeats, sweeprate=sweeprate, delay=0.1, alternate=0, comments=comments, use_awg=1,  nosave=nosave)
		
		rampmultiplefdac(fd, sweepgate, mid)
		i++
	while (i<num)
	sc_ResampleFreqCheckfadc = resample_state
end



function ScanTransition([num_scans, sweeprate, width, ramprate, repeats, center_first, center_gate, center_width, sweep_gate, additional_comments, mid, cs_target, csqpc_gate, alternate, fadcchannel, gate_divider, delayy, nosave, virtual_gates, virtual_ratios, virtual_mids, use_AWG])
	variable num_scans, sweeprate, width, ramprate, repeats, center_first, center_width, mid, cs_target, alternate, fadcchannel, gate_divider, delayy, nosave, use_AWG
	string center_gate, sweep_gate, additional_comments, csqpc_gate, virtual_gates, virtual_ratios, virtual_mids
	
	if (!paramisdefault(virtual_gates) && (paramisdefault(virtual_mids) || paramisdefault(virtual_ratios) ))
	 ABORT "ERROR[ScanTransition]: virtual_gates specified but virtual_mids or virtual_ratios MISSING"
	endif

	num_scans = (num_scans == 0) ? 1 : num_scans
	sweeprate = paramisdefault(sweeprate) ? 100 : sweeprate
	width = paramisdefault(width) ? 2000 : width
	repeats = paramIsDefault(repeats) ? 10 : repeats
	gate_divider = paramisdefault(gate_divider) ? 20 : gate_divider
	delayy = paramisdefault(delayy) ? 0.01 : delayy
	fadcchannel = paramisdefault(fadcchannel) ? 1 : fadcchannel
	use_AWG = paramisdefault(use_AWG) ? 0 : use_AWG

	// let center_first default to 0
	sweep_gate = selectstring(paramisdefault(sweep_gate), sweep_gate, "P*200")
	center_gate = selectstring(paramisdefault(center_gate), center_gate, "P*2")
	center_width = paramisDefault(center_width) ? 20 : center_width
	additional_comments = selectstring(paramisdefault(additional_comments), additional_comments, "")
	csqpc_gate = selectstring(paramisdefault(csqpc_gate), csqpc_gate, "CSQ2*20")

	string comments
	variable i
	for(i=0;i<num_scans;i++)
		if (center_first)
			variable center_gate_mid
			if (!paramisdefault(virtual_gates) && !paramisdefault(virtual_mids))
			   	rampmultipleChannels(virtual_gates, virtual_mids) // ramp virtual gates
			endif
			rampmultipleChannels(sweep_gate, num2str(mid))
			center_gate_mid = centerontransition(gate=center_gate, width=center_width, single_only=1)
			mid = (cmpstr(center_gate, sweep_gate) == 0) ? center_gate_mid : mid  // If centering with sweepgate, update the mid value
			
			printf "Centered at %s=%.2f mV\r" center_gate, center_gate_mid
			if (paramisdefault(virtual_gates))
				rampmultipleChannels(sweep_gate, num2str(-width*0.5)) // only ramp to outside transition if not a virtual scan
			endif
			
			set_indep() // dirty fix
			
			if (!paramisdefault(cs_target))
				CorrectChargeSensor(fdchannelstr=csqpc_gate, fadcchannel=fadcchannel, check=0, direction=1, gate_divider=gate_divider, natarget=cs_target)
			else
				CorrectChargeSensor(fdchannelstr=csqpc_gate, fadcchannel=fadcchannel, check=0, direction=1, gate_divider=gate_divider)
			endif
		endif
		
		sprintf comments, "transition"
		if (repeats > 1)
			sprintf comments, "%s, repeat, " comments
		endif
		
		if (num_scans > 1)
			sprintf comments, "%s, scan_num=%d, " comments, i
		endif
		
		if (!paramisdefault(virtual_gates) && !paramisdefault(virtual_mids))
			string starts, fins, sweep_channels
			calculate_virtual_starts_fins_using_ratio(mid, width, sweep_gate, virtual_gates, virtual_mids, virtual_ratios, sweep_channels, starts, fins)	
		
			ScanFastDAC(0, 0, sweep_channels, repeats=repeats, sweeprate=sweeprate, ramprate=ramprate, starts=starts, fins=fins, delay=delayy, comments=comments + additional_comments, alternate=alternate, nosave=nosave, use_AWG=use_AWG)
			rampmultipleChannels(virtual_gates, virtual_mids)
			rampmultipleChannels(sweep_gate, num2str(mid))	
		
		else 
			ScanFastDAC(mid-width, mid+width, sweep_gate, repeats=repeats, sweeprate=sweeprate, ramprate=ramprate, delay=delayy, comments=comments + additional_comments, alternate=alternate, nosave=nosave, use_AWG=use_AWG)
			rampmultipleChannels(sweep_gate, num2str(mid))	
		endif
	
	endfor
end


function ScanWithVirtualRatios(mid_x, width_x, channelx, sweeprate, [comments, mid_y, width_y, channely, numptsy, virtual_x_gates, virtual_x_ratios, virtual_x_mids, virtual_y_gates, virtual_y_ratios, virtual_y_mids, delayy, repeats, alternate, interlaced_channels, interlaced_setpoints, use_awg]) 
	// Basically a wrapper for the usual scan functions to allow for using virtual gates where the sweep ratio is known, but the exact start/end values are not
	// Note: channelx (and channely) are intended to be a single channel only, if you want multiple channels to sweep the same, just add the second as a virtual gate with ratio 1
	variable mid_x, width_x, sweeprate, mid_y, width_y, numptsy, delayy, repeats, alternate, use_awg
	string channelx, channely, comments, virtual_x_gates, virtual_x_ratios, virtual_x_mids, virtual_y_gates, virtual_y_ratios, virtual_y_mids, interlaced_channels, interlaced_setpoints

	delayy = ParamIsDefault(delayy) ? 0.01 : delayy
	comments = selectstring(paramisdefault(comments), comments, "")
	interlaced_channels = selectString(paramisdefault(interlaced_channels), interlaced_channels, "")
	interlaced_setpoints = selectString(paramisdefault(interlaced_setpoints), interlaced_setpoints, "")
	
	/////// Convert X (and Y) parameters into channels/starts/fins (that the other functions already take) ///////
	//// Xs
	string channelsx, startxs, finxs
	if (!paramIsDefault(virtual_x_gates))
		calculate_virtual_starts_fins_using_ratio(mid_x, width_x, channelx, virtual_x_gates, virtual_x_mids, virtual_x_ratios, channelsx, startxs, finxs)
	else
		channelsx = channelx
		startxs = num2str(mid_x - width_x)
		finxs = num2str(mid_x + width_x)
	endif
	
	//// Ys (if using)
	if (!paramisdefault(channely))
		string channelsy, startys, finys	
		//// IF USING VIRTUAL Ys ////
		if (!paramIsDefault(virtual_y_gates))
			calculate_virtual_starts_fins_using_ratio(mid_y, width_y, channely, virtual_y_gates, virtual_y_mids, virtual_y_ratios, channelsy, startys, finys)
		else
			channelsy = channely
			startys = num2str(mid_y - width_y)
			finys = num2str(mid_y + width_y)
		endif
	endif
	
	nvar fd
	//// DECIDE WHICH SCAN FUNCTION TO PASS TO ////
	// IF INTERLACED_Y
	if (!paramisDefault(interlaced_channels) && !paramIsDefault(channely))
		ScanFastDAC2D(0, 0, channelsx, 0, 0, channelsy, numptsy,  sweeprate=sweeprate, delayy=delayy, startxs=startxs, finxs=finxs, startys=startys, finys=finys, comments=comments, nosave=0, use_AWG=use_awg, interlaced_channels=interlaced_channels, interlaced_setpoints=interlaced_setpoints)
	// IF REGULAR 1D	
	elseif (paramIsDefault(channely))
		ScanFastDAC(0, 0, channelsx, sweeprate=sweeprate, delay=delayy, repeats=repeats, alternate=alternate, starts=startxs, fins=finxs, comments=comments, nosave=0, use_awg=use_awg,  interlaced_channels=interlaced_channels, interlaced_setpoints=interlaced_setpoints)
	// IF REGULAR 2D
	else
		ScanFastDAC2D(0, 0, channelsx, 0, 0, channelsy, numptsy,  sweeprate=sweeprate, delayy=delayy, startxs=startxs, finxs=finxs, startys=startys, finys=finys, comments=comments, nosave=0, use_AWG=use_awg)
	endif

	/////// Gates back to Middle values (Usually nicer than having them left at the end of a scan)
	// X gates
	RampMultipleChannels(channelx, num2str(mid_x))
	if (!paramIsDefault(virtual_x_gates))
		RampMultipleChannels(virtual_x_gates, virtual_x_mids)
	endif
	// Y gates
	if (!paramisdefault(channely))
		RampMultipleChannels(channely, num2str(mid_y))
		if (!paramIsDefault(virtual_y_gates))
			RampMultipleChannels(virtual_y_gates, virtual_y_mids)
		endif
	endif

end




function ScanTransitionMany()
	nvar fd

	make/o/free Var1  = {-440, 	-410,	-400,	-385,	-356,	-331,	-307,	-281,	-257,	-231,	-205}  // ACC*2
	make/o/free Var1b = {-25, 	-100,	-150,	-200,	-300,	-400,	-500,	-600,	-700,	-800,	-900}  // SDP
	make/o/free Var2 = {0}
	make/o/free Var3 = {0}

	variable numi = numpnts(Var1), numj = numpnts(Var2), numk = numpnts(Var3)
	variable ifin = numi, jfin = numj, kfin = numk
	variable istart, jstart, kstart

	// Starts
	istart=0; jstart=0; kstart=0

	// Fins
	ifin=ifin; jfin=jfin; kfin=kfin


	string comments
	variable mid

	variable i, j, k, repeats
	i = istart; j=jstart; k=kstart
	for(k=kstart;k<kfin;k++)  // Loop for change k var 3
		kstart = 0
		for(j=jstart;j<jfin;j++)	// Loop for change j var2
			jstart = 0
			for(i=istart;i<ifin;i++) // Loop for changing i var1 and running scan
				istart = 0
				printf "Starting scan at i=%d, SDP = %.1fmV \r", i, Var1b[i]
				rampmultiplefdac(fd, "ACC*2", Var1[i])
				rampmultiplefdac(fd, "SDP", Var1b[i])
				for(repeats=0;repeats<1;repeats++)
//					ScanEntropyRepeat(num=1, center_first=1, balance_multiplier=1, width=200, hqpc_bias=25, additional_comments="0->1 transition", repeat_multiplier=1, freq=12.5, sweeprate=25, two_part=0, repeats=5, center=0)
					ScanTransition(sweeprate=25, width=400, repeats=2, center_first=1, center_gate="ACC*2", center_width=20, sweep_gate="ACC*400", additional_comments="rough check before entropy scans", csqpc_gate="CSQ")
				endfor
			endfor
		endfor
	endfor

	print "Finished all scans"
end


///////////////////////////////////////////////////////////////////////////////////////////
/////////////////////// MISCELLANEOUS /////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////

function DCbiasRepeats(max_current, num_steps, duration, [voltage_ratio])
	// DCBias measurements with ScanFastDACRepeat at each value (rather than a continuously changing 2D plot)
	// Note: Assumes already lined up on transition
	variable max_current // Max current in nA through heater
	variable num_steps  // Number of steps from 0 -> max_current
	variable duration  // Duration of scan at each step
	variable voltage_ratio  // Proportional Voltage to use to offset potential created by current bias (all in mV from DAC)

	voltage_ratio = paramisDefault(voltage_ratio) ? 1.478 : voltage_ratio
	variable current_resistor = 10 // Mohms of resistance current bias is driven through
	variable scan_width = 500
	variable sweeprate = 2000
	string current_channel = "OHC(10M)"
	string voltage_channel = "OHV*1000"

	nvar fd
	string comments
	variable repeats

	repeats = round((duration/(scan_width*2/sweeprate)))  // Desired duration / (scan width/sweeprate)

	// Measure with zero bias
	rampmultipleFDAC(fd, current_channel, 0)
	rampmultipleFDAC(fd, voltage_channel, 0)
	sprintf comments, "DCbias Repeat, zero bias"
	ScanFastDAC(-scan_width, scan_width, "ACC*400", repeats=repeats, sweeprate=sweeprate, comments=comments, nosave=0)

	// Measure with non-zero bias
	variable setpoint
	variable i
	for (i=1; i<num_steps+1; i++)  // Start from 1 for only non-zero bias
		setpoint = i*(max_current*10/num_steps)

		// Measure positive bias
		rampmultipleFDAC(fd, current_channel, setpoint)
		rampmultipleFDAC(fd, voltage_channel, -setpoint*voltage_ratio)
		sprintf comments, "DCbias Repeat, %.3f nA" setpoint/current_resistor
		ScanFastDAC(-scan_width, scan_width, "ACC*400", repeats=repeats, sweeprate=sweeprate, comments=comments, nosave=0)

		// Measure negative bias
		rampmultipleFDAC(fd, current_channel, -setpoint)
		rampmultipleFDAC(fd, voltage_channel, setpoint*voltage_ratio)
		sprintf comments, "DCbias Repeat, %.3f nA" -setpoint/current_resistor
		ScanFastDAC(-scan_width, scan_width, "ACC*400", repeats=repeats, sweeprate=sweeprate, comments=comments, nosave=0)

	endfor

	// Return to zero heating
	rampmultipleFDAC(fd, current_channel, 0)
	rampmultipleFDAC(fd, voltage_channel, 0)
end





function QPCProbe(InstrID, channels, [scan_time, max_voltage, steps, delay, repeats, comments])
   variable InstrID
	string channels, comments
	variable scan_time, max_voltage, steps, delay, repeats
	
	
	scan_time = paramisdefault(scan_time)? 30 : scan_time
	max_voltage = paramisdefault(max_voltage)? -1200 : max_voltage
	steps = paramisdefault(steps)? 50 : steps
	delay = paramisdefault(delay)? 0 : delay
	repeats = paramisdefault(repeats)? 6 : repeats
	comments = selectstring(paramisdefault(comments), comments, "")
	
	variable i
	variable sweeprate
	for(i = -steps; abs(i) <= abs(max_voltage); i-=steps)
       printf "Scanning 0 -> %d\r"i
       sweeprate = abs(i/scan_time)
       ScanFastDAC(0, i, channels, sweeprate=sweeprate, delay=delay, repeats=repeats, alternate=1)

	endfor
	
	
end





