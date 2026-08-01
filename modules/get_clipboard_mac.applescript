use framework "Foundation"
use framework "AppKit"

on run argv
    if (count of argv) < 1 then
        return "NO_PATH"
    end if
    
    set destPath to item 1 of argv
    
    set pb to current application's NSPasteboard's generalPasteboard()
    set imgData to pb's dataForType:(current application's NSPasteboardTypePNG)
    
    if imgData is missing value then
        set imgData to pb's dataForType:(current application's NSPasteboardTypeTIFF)
        if imgData is not missing value then
            set rep to current application's NSBitmapImageRep's imageRepWithData:imgData
            if rep is not missing value then
                set imgData to rep's representationUsingType:(current application's NSPNGFileType) properties:(missing value)
            end if
        end if
    end if

    if imgData is not missing value then
        imgData's writeToFile:destPath atomically:true
        return "SUCCESS"
    else
        return "NO_IMAGE"
    end if
end run
