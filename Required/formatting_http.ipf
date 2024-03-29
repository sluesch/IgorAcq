#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3				// Use modern global access method and strict wave access
#pragma DefaultTab={3,20,4}		// Set default tab width in Igor Pro 9 and later

//////////////////
/// HTTP INSTR ///
//////////////////


function openHTTPinstr(mandatory, [options, verbose])
	string mandatory // mandatory: "name= ,instrID= ,url = "
	string options   // options: "test_ping= "
	variable verbose

	if(paramisdefault(options))
		options=""
	endif
	
	if(paramisdefault(verbose))
		verbose=1
	elseif(verbose!=1)
		verbose=0
	endif
	
	// create global variable
	string name = StringByKey("name", mandatory, "=", ",")
	string url = StringByKey("url", mandatory, "=", ",")
	string var_name = StringByKey("instrID", mandatory, "=", ",")

	string /g $var_name = url
	if(verbose==1)
		printf "%s (%s) connected as %s\r", name, url, var_name
	endif

	if(strlen(options)>0)
	
		// run test query
		string cmd
		cmd = StringByKey("test_ping",options,"=", ",")
		if(strlen(cmd)>0)
			
			// do something here with that command
			string response = ""
			
			if(verbose)
				printf "\t-- %s responded with: %s\r", name, response
			endif
		else
			if(verbose)
				printf "\t-- No test\r"
			endif
		endif

	endif

end


function/s postHTTP(instrID,cmd,payload,headers)
	string instrID, cmd, payload, headers
	string response=""

//	print instrID+cmd, payload
	URLRequest /TIME=15.0 /DSTR=payload url=instrID+cmd, method=post, headers=headers

	if (V_flag == 0)    // No error
		response = S_serverResponse // response is a JSON string
		if (V_responseCode != 200)  // 200 is the HTTP OK code
			print "[ERROR] HTTP response code " + num2str(V_responseCode)
			if(strlen(response)>0)
		   	printf "[MESSAGE] %s\r", getJSONvalue(response, "error")
		   endif
		   return ""
		else
			return response
		endif
   else
        abort "HTTP connection error."
   endif
end


function/s putHTTP(instrID,cmd,payload,headers)
	string instrID, cmd, payload, headers
	string response=""

//	print "url=",instrID+cmd
//	print "payload=", payload
//	print headers
	
	URLRequest /TIME=15.0 /DSTR=payload url=instrID+cmd, method=put, headers=headers

	if (V_flag == 0)    // No error
		response = S_serverResponse // response is a JSON string
		print V_responseCode
		print V_flag
		if (V_responseCode != 200)  // 200 is the HTTP OK code
			print "[ERROR] HTTP response code " + num2str(V_responseCode)
			if(strlen(response)>0)
		   	printf "[MESSAGE] %s\r", getJSONvalue(response, "error")
		   endif
		   return ""
		else
			return response
		endif
   else
        abort "HTTP connection error."
   endif
end


function/s getHTTP(instrID,cmd,headers)
	string instrID, cmd, headers
	string response, error

//	print instrID+cmd
	URLRequest /TIME=25.0 url=instrID+cmd, method=get, headers=headers

	if (V_flag == 0)    // No error
		response = S_serverResponse // response is a JSON string
		if (V_responseCode != 200)  // 200 is the HTTP OK code
			print "[ERROR] HTTP response code " + num2str(V_responseCode)
		   return ""
		else
			return response
		endif
   else
    	print "HTTP connection error."
		return ""
   endif
end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////Json functions//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/////////////
/// JSON  ///
/////////////

//// Using JSON XOP ////  

// Using JSON XOP requires working with JSON id's rather than JSON strings.
// To be used in addition to home built JSON functions which work with JSON strings
// JSON id's give access to all XOP functions (e.g. JSON_getKeys(jsonID, path))
// functions here should be ...JSONX...() to mark as a function which works with JSON XOP ID's rather than strings
// To switch between jsonID and json strings use JSON_Parse/JSON_dump 

function getJSONXid(jsonID, path)
	// Returns jsonID of json object located at "path" in jsonID passed in. e.g. get "BabyDAC" json from "Sweep_logs" json.
	// Path should be able to be a true JSON pointer i.e. "/" separated path (e.g. "Magnets/Magx") but it is untested
	variable jsonID
	string path
	variable i, tempID
	string tempKey
	
	if (JSON_GetType(jsonID, path) != 0)	
		abort "ERROR[get_json_from_json]: path does not point to JSON obect"
	endif

	if (itemsinlist(path, "/") == 1)
		return getJSONXid_fromKey(jsonID, path)
	else
		tempID = jsonID
		for(i=0;i<itemsinlist(path, "/");i++)  //Should recursively get deeper JSON objects. Untested
			tempKey = stringfromlist(i, path, "/")
			tempID = getJSONXid_fromKey(tempID, tempkey)
		endfor
		return tempID
	endif
end
	
function getJSONXid_fromKey(jsonID, key)
	// Should only be called from getJSONid to convert the inner JSON into a new JSONid pointer.
	// User should use the more general getJSONid(jsonID, path) where path can be a single key or "/" separated path
	variable jsonID
	string key
	if ((JSON_GetType(jsonID, key) != 0) || (itemsinlist(key, "/") != 1)	)
		abort "ERROR[get_json_from_json_key]: key is not a top level JSON obect"
	endif
	return JSON_parse(getJSONvalue(json_dump(jsonID), key))  // workaround to get a jsonID of inner JSON
end

function sc_confirm_JSON(jsonwave, [name])
	//Checks whether 'jsonwave' can be parsed as a JSON
	// Where 'jsonwave' is a textwave built from the homemade json functions NOT JSON_XOP
	//name is just to make it easier to identify the error
	wave/t jsonwave
	string name
	if (paramisDefault(name))
		name = ""
	endif

	JSONXOP_Parse/z jsonwave[0]
	if (v_flag != 0)
		printf "WARNING: %s JSON is not a valid JSON (saved anyway)\r", name
	endif
end			
//// END of Using JSON XOP ////

function/s addJSONkeyval(JSONstr,key,value,[addquotes])
	// returns a valid JSON string with a new key,value pair added.
	// if JSONstr is empty, start a new JSON object
	string JSONstr, key, value
	variable addquotes
	
	// check value, can't be an empty string
	if(strlen(value)==0)
		value = "null"
	endif

	if(!paramisdefault(addquotes))
		if(addquotes==1)
			// escape quotes in value and wrap value in outer quotes
			value = "\""+escapeQuotes(value)+"\""
		endif
	endif
	
	if(strlen(JSONstr)!=0)
		// remove all starting brackets, whitespace or plus signs
		variable i=0
		do
			if((isWhitespace(JSONstr[i])==1) || (CmpStr(JSONstr[i],"{")==0) || (CmpStr(JSONstr[i],"+")==0))
				i+=1
			else
				break
			endif
		while(1)

		// remove single ending bracket + whitespace
		variable j=strlen(JSONstr)-1
		do
			if((isWhitespace(JSONstr[j])==1))
				j-=1
			elseif((CmpStr(JSONstr[j],"}")==0))
				j-=1
				break
			else
				print "[ERROR] Bad JSON string in addJSONkeyvalue(...): "+JSONstr
				break
			endif
		while(1)

		return "{"+JSONstr[i,j]+", \""+key+"\":"+value+"}"
	else
		return "{"+JSONstr[i,j]+"\""+key+"\":"+value+"}"
	endif

end

function/s getIndent(level)
	// returning whitespace for formatting strings
	// level = # of tabs, 1 tab = 4 spaces
	variable level

	variable i=0
	string output = ""
	for(i=0;i<level;i+=1)
		output += "    "
	endfor

	return output
end

function /s prettyJSONfmt(jstr)
	// this could be much prettier
	string jstr
	string output="", key="", val=""
	
	// Force Igor to clear out this before calling JSONSimple because JSONSimple does sort of work, but throws an error which prevents it from clearing out whatever was left in from the last call
	make/o/T t_tokentext = {""}  

	JSONSimple/z jstr
	wave w_tokentype, w_tokensize, w_tokenparent
	variable i=0, indent=1
	
	// Because JSONSimple is awful, it leaves a random number of empty cells at the end sometimes. So remove them
	FindValue /TEXT="" t_tokentext
	Redimension/N=(V_row) t_tokentext


	output+="{\n"
	for(i=1;i<numpnts(t_tokentext)-1;i+=1)

		// print only at single indent level
		if ( w_tokentype[i]==3 && w_tokensize[i]>0 )
			if( w_tokenparent[i]==0 )
				indent = 1
				if( w_tokentype[i+1]==3 )
					val = "\"" + t_tokentext[i+1] + "\""
				else
					val = t_tokentext[i+1]
				endif
				key = "\"" + t_tokentext[i] + "\""
				output+=(getIndent(indent)+key+": "+val+",\n")
			endif
		endif
	endfor

	return output[0,strlen(output)-3]+"\n}\n"
end

function/s getJSONindices(keys)
	// returns string list with indices of parsed keys
	string keys
	string indices="", key
	wave/t t_tokentext
	wave w_tokentype, w_tokensize, w_tokenparent
	variable i=0, j=0, index, k=0

	for(i=0;i<itemsinlist(keys,":");i+=1)
		key = stringfromlist(i,keys,":")
		if(i==0)
			index = 0
		else
			index = str2num(stringfromlist(i-1,indices,","))
		endif
		for(j=0;j<numpnts(t_tokentext);j+=1)
			if(cmpstr(t_tokentext[j],key)==0 && w_tokensize[j]>0)
				if(w_tokenparent[j]==index)
					if(w_tokensize[j+1]>0)
						k = j+1
					else
						k = j
					endif
					indices = addlistitem(num2str(k),indices,",",inf)
					break
				endif
			endif
		endfor
	endfor

	return indices
end

function/s getJSONkeyoffset(key,offset)
	string key
	variable offset
	wave/t t_tokentext
	wave w_tokentype, w_tokensize
	variable i=0

	// find key and check that it is infact a key
	for(i=offset;i<numpnts(t_tokentext);i+=1)
		if(cmpstr(t_tokentext[i],key)==0 && w_tokensize[i]>0)
			return t_tokentext[i+1]
		endif
	endfor
	// if key is not found, return an empty string
	print "[ERROR] JSON key not found: "+key
	return t_tokentext[0] // Default to return everything
end

/// read ///
function/s getJSONvalue(jstr, key)
	// returns the value of the parsed key
	// function returns can be: object, array, value
	// expected format: "parent1:parent2:parent3:key"
	string jstr, key
	variable offset, key_length
	string indices
	
	key_length = itemsinlist(key,":")

	JSONSimple/z jstr
	wave/t t_tokentext
	wave w_tokentype, w_tokensize

	if(key_length==0)
		// return whole json
		return jstr
	elseif(key_length==1)
		// this is the only key with this name
		// if not, the first key will be returned
		offset = 0
		return getJSONkeyoffset(key,offset)
	else
		// the key has parents, and there could be multiple keys with this name
		// find the indices of the keys parsed
		indices = getJSONindices(key)
		if(itemsinlist(indices,",")<key_length)
			print "[ERROR] Value of JSON key is ambiguous: "+key
			return ""
		else
			return getJSONkeyoffset(stringfromlist(key_length-1,key,":"),str2num(stringfromlist(key_length-1,indices,","))-1)
		endif
	endif
end
//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////
////////////////////////////////More functions migrated from Scancontroller IO////////////////
//////////////////////////////////////////////////////////////////////////////////////////////

function /S escapeQuotes(str)
	string str

	variable i=0, escaped=0
	string output = ""
	do

		if(i>strlen(str)-1)
			break
		endif

		// check if the current character is escaped
		if(i!=0)
			if( CmpStr(str[i-1], "\\") == 0)
				escaped = 1
			else
				escaped = 0
			endif
		endif

		// escape quotes
		if( CmpStr(str[i], "\"" ) == 0 && escaped == 0)
			// this is an unescaped quote
			str = str[0,i-1] + "\\" + str[i,inf]
		endif
		i+=1

	while(1)
	return str
end

function /S unescapeQuotes(str)
	string str

	variable i=0, escaped=0
	string output = ""
	do

		if(i>strlen(str)-1)
			break
		endif

		// check if the current character is escaped
		if(i!=0)
			if( CmpStr(str[i-1], "\\") == 0)
				escaped = 1
			else
				escaped = 0
			endif
		endif

		// escape quotes
		if( CmpStr(str[i], "\"" ) == 0 && escaped == 1)
			// this is an unescaped quote
			str = str[0,i-2] + str[i,inf]
		endif
		i+=1

	while(1==1)
	return str
end

/////////////////////////////////
/// text formatting utilities ///
/////////////////////////////////

Function isWhiteSpace(char)
    String char

    return GrepString(char, "\\s")
End

Function/S removeLeadingWhitespace(str)
    String str

    if (strlen(str) == 0)
        return ""
    endif

    do
        String firstChar= str[0]
        if (IsWhiteSpace(firstChar))
            str= str[1,inf]
        else
            break
        endif
    while (strlen(str) > 0)

    return str
End


function/S removeSeperator(str, sep)
	string str, sep
	if (strlen(str) == 0)
        return ""
   endif
    
   do
   		String lastChar = str[strlen(str) - 1]
       if (!cmpstr(lastChar, sep))
       	str = str[0, strlen(str) - 2]
       else
        	break
       endif
   while (strlen(str) > 0)
   
   do
   		String firstChar= str[0]
      	if (!cmpstr(firstChar, sep))
       	str= str[1,inf]
      	else
         	break
      	endif
   while (strlen(str) > 0)
   
   return str

end 

function/S removeTrailingWhitespace(str)
    String str

    if (strlen(str) == 0)
        return ""
    endif

    do
        String lastChar = str[strlen(str) - 1]
        if (IsWhiteSpace(lastChar))
            str = str[0, strlen(str) - 2]
        else
        	break
        endif
    while (strlen(str) > 0)
    return str
End

function/s removeWhiteSpace(str)
	// Remove leading or trailing whitespace
	string str
	str = removeLeadingWhitespace(str)
	str = removeTrailingWhitespace(str)
	return str
end

function countQuotes(str)
	// count how many quotes are in the string
	// +1 for "
	// escaped quotes are ignored
	string str
	variable quoteCount = 0, i = 0, escaped = 0
	for(i=0; i<strlen(str); i+=1)

		// check if the current character is escaped
		if(i!=0)
			if( CmpStr(str[i-1], "\\") == 0)
				escaped = 1
			else
				escaped = 0
			endif
		endif

		// count quotes
		if( CmpStr(str[i], "\"" ) == 0 && escaped == 0)
			quoteCount += 1
		endif

	endfor
	return quoteCount
end


function/s removeLiteralQuotes(str)
	// removes single outermost quotes
	// double quotes only
	string str

	variable i=0, openQuotes=0
	for(i=0;i<strlen(str);i+=1)
		if(CmpStr(str[i],"\"")==0)
			openQuotes+=1
		endif

		if(openQuotes>0 && CmpStr(str[i],"\"")!=0)
			break
		endif
	endfor

	if(openQuotes==0)
		print "[ERROR] String not surrounded by quotes. str: "+str
		return ""
	elseif(openQuotes==2)
		openQuotes=1
	elseif(openQuotes>3)
		openQuotes=3
	endif

	str = str[i,inf]
	variable j, closeQuotes=0
	for(j=strlen(str); j>0; j-=1)

		if(CmpStr(str[j],"\"")==0)
			closeQuotes+=1
		endif

		if(closeQuotes==openQuotes)
			break
		endif

	endfor

	return str[0,j-1]
end

function/t removeStringListDuplicates(theListStr)
	// credit: http://www.igorexchange.com/node/1071
	String theListStr

	String retStr = ""
	variable ii
	for(ii = 0 ; ii < itemsinlist(theListStr) ; ii+=1)
		if(whichlistitem(stringfromlist(ii , theListStr), retStr) == -1)
			retStr = addlistitem(stringfromlist(ii, theListStr), retStr, ";", inf)
		endif
	endfor
	return retStr
End

function/s searchFullString(string_to_search,substring)
	string string_to_search, substring
	string index_list=""
	variable test, startpoint=0

	do
		test = strsearch(string_to_search, substring, startpoint)
		if(test != -1)
			index_list = index_list+num2istr(test)+","
			startpoint = test+1
		endif
	while(test > -1)

	return index_list
end

