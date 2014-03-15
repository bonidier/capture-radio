# Introduction

Capture-Radio is a pure bash script to save audio streams from your prefered (web)radios for a user-defined duration


# configuration

you should create a radio-list.txt file

it can contains HTTP audio streams (like mp3,AAC,Ogg), or playlists (M3U and PLS)

here is the radio-list.txt.dist content for example :

```
a_Uniq_tag1|http://url_to_your_prefered/radio1.m3u
a_Uniq_tag2|http://url_to_your_prefered/radio2.pls
a_Uniq_tag3|http://url_to_your_prefered/radio3.mp3
a-Uniq-tag4|http://url_to_your_prefered/radio4.aac
a-Uniq-tag5|http://url_to_your_prefered_radio5_stream
```

# usage

- get embedded help :

```
 ./capture-radio.sh
 ./capture-radio.sh -h
```

- get available tags (radios list) :

```
 ./capture-radio.sh -l
```

- get available streams for a tag :

```
  ./capture-radio.sh -t [radio_tag]
```  

- launch capture of a radio :

```
  ./capture-radio.sh -t [radio_tag] -d [capture duration in seconds]
```

  if the radio's playlist has more than one stream, will show them instead of starting

- launch capture of a defined radio's stream :

```
  ./capture-radio.sh -t [radio_tag] -d [capture duration in seconds] -s [stream_number]
```


# additional informations

## Tree structure
|directory|description|
|---|---|
| **captured/** | final destination for your captures |
| **db/** | cache for playlist and streams, to download playlist only if needed |
| **logs/** | not used, you can store script output here |
| **working/** | temporary capture file storage during download |
  

## when finishing capture  

when finishing, capture-radio try to determine file type for captured file, to add correct extension to file
if can't, you'll see a fake extension

Final file will be stored in captured/your_radio_tag/your_radio_tag.[range-of-capture].extension

# scheduling

If you are a good auditor and can't miss your favorite programm at fixed time,
(if at work, on holidays, far away from radio)
you can schedule a cronjob like it : 

```
0 0 * * * (cd ~/capture-radio/; ./capture-radio.sh -t myradio -d 7200 &> logs/output-myradio.log)
0 9 * * * (cd ~/capture-radio/; ./capture-radio.sh -t my-other-radio -d 3600 -s123 &> logs/output.my-other-radio.log)
```

