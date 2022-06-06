#!/bin/sh

reqHeight=1080												#declare target resolution height
reqWidth=-1													#declare target resolution width (setted as -1 to maintain aspect ratio)
isSmallResolution=0											#flag to check if input video has less resolution than target resolution
reducingFactor=0.1											#percentage to which video size needs to be reduced
CBR=1000

#get input video bit rate
videoBitRate=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of compact=p=0:nk=1 $1)
videoBitRate=$(($videoBitRate/1000))						#convert input video bit rate to kb
originalBitRate=$(($videoBitRate))							#store input video bit rate for future ref


#get input video height
inputVideoHeight=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 $1)
if (($inputVideoHeight < $reqHeight));						#check if input video height is less than target height
then
	reqHeight=$inputVideoHeight
	isSmallResolution=1
fi

hasAudio="v:0"												#flag to check if input video has audio

#check if input video has audio
f=$(ffprobe -v fatal -of default=nw=1:nk=1 -show_streams -select_streams a -show_entries stream=codec_type $1)
if [ -n "$f" ];
then
 hasAudio="v:0,a:0"
fi

videoBitRate=$(echo $videoBitRate*$reducingFactor | bc)	 	#reduce input video bitrate by reducing factior percentage
videoBitRate=${videoBitRate%.*}

#after reducing check if bitrate is less than 1000
if (( $videoBitRate < $CBR ));
then
	if (( $originalBitRate < $CBR ));						#check if input video bit rate is less than 1MB
	then													#if yes then  
		videoBitRate=$originalBitRate						#set required bit rate same as input video bitrate
	else													#else
		videoBitRate=$CBR									#set required bit rate to 1MB
	fi
fi

minVideoBitRate=$(($videoBitRate-$CBR))						#set minimum bit rate
maxVideoBitRate=$(($videoBitRate))							#set maximum bit rate
buff=$(($videoBitRate*2))									#set buffer

if (( $minVideoBitRate < 0 ));								#check if minimum bit rate is negative
then
	minVideoBitRate=$videoBitRate
	maxVideoBitRate=$videoBitRate+50
fi

#append k to denote KB in bit rates
videoBitRateM=$(($videoBitRate))k
minVideoBitRateM=$(($minVideoBitRate))k
maxVideoBitRateM=$(($maxVideoBitRate))k
buffM=$(($buff))k

#encoding ffmpeg command
ffmpeg -i $1 \
	-filter_complex \
	"[0:v]split=1[v1]; \
	[v1]scale=w=$reqWidth:h=$reqHeight[v1out]" \
	-map [v1out] -c:v:0 libx264 -x264-params "nal-hrd=cbr:force-cfr=1" -b:v:0 $videoBitRateM -maxrate:v:0 $maxVideoBitRateM -minrate:v:0 $minVideoBitRateM -bufsize:v:0 $buffM -crf 17 -preset faster -g 48 -sc_threshold 0 -keyint_min 48 \
	-map a?:0 -c:a:0 aac -b:a:0 96k -ac 2 \
	-f hls \
	-hls_time 15 \
	-hls_list_size 100 \
	-hls_flags independent_segments \
	-hls_segment_type mpegts \
	-hls_segment_filename $2_stream_%v/data%02d.ts \
	-master_pl_name $2_master.m3u8 \
	-var_stream_map $hasAudio $2_stream_%v/index.m3u8
