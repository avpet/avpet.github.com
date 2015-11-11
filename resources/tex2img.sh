#!/bin/sh
# sh tex2img <filename>

texfilename="$1"

filename="${texfilename%.*}"

echo $filename

pdftex $1

dvips "$filename.dvi"

ps2pdf "$filename.ps"

pdftoppm -png "$filename.pdf" > "$filename.png"

#convert "$filename.png" -crop 660x55+50+65 "$filename_.png"
convert "$filename.png" -crop 680x375+210+200 "$filename_.png"

rm "$filename.png"

mv "$filename_.png" "$filename.png"

rm "$filename.aux" "$filename.dvi" "$filename.log" "$filename.pdf" "$filename.ps"

exit 0
