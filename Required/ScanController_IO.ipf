#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3				// Use modern global access method and strict wave access
#pragma DefaultTab={3,20,4}		// Set default tab width in Igor Pro 9 and later

Function StringToListWave(string strList)
    // Takes a string of numbers delimited by either commas or semicolons and converts it to a numeric wave.
    
    Variable numItems, i
    String numStr, separator
    
    // Determine the separator used in the string
    If (StrSearch(strList, ";", 0) >= 0)
        separator = ";"
    ElseIf (StrSearch(strList, ",", 0) >= 0)
        separator = ","
    Else
        // If no separator is found, assume the string is invalid or empty and abort
        Print "No valid separator found or string is empty."
        return 0
    EndIf
    
    // Count the number of items in the list
    numItems = ItemsInList(strList, separator)
    
    // Make a new wave with the number of items found in the string
    Make/O/N=(numItems) numericWave
    
    // Loop through the string, convert each item to a number, and assign it to the wave
    For (i = 0; i < numItems; i += 1)
        numStr = StringFromList(i, strList, separator)  // Extract number string from list using the detected separator
        numericWave[i] = Str2Num(numStr)  // Convert to number and assign to wave
    EndFor
    
    // Optionally, give the wave a meaningful name or handle it externally
End
