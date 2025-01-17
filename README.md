# amenbreak

a dedicated amen break script for norns.

![inspiration](https://user-images.githubusercontent.com/6550035/208136642-1081aa03-8e32-487a-b282-fd7130da05fc.png)


## Requirements

- norns
- at least 150MB of disk space

## Documentation


![amenbreak](https://user-images.githubusercontent.com/6550035/208138151-5d2cc8a9-bc64-4e12-b92e-87a12f1e9c35.png)

### quickstart

E2 amens, E3 breaks.


### features

- over 200 amen break samples (from [internet archive](https://archive.org/details/amen-breaks-compilation)), loaded into memory for instant playback
- automatic stutter/stretch/delay effects (amen+break)
- overdrive/decimate/degrade control (punch)
- kick drum added to bolster kicks of pre-analyzed samples
- edit mode allows manipulating individual slices/kick volume
- all effects are determined by probabilities with sweet spots controlled by many different [easing functions](https://www.desmos.com/calculator/3mmmijzncm) (thanks to @dewb for pointing this out)
- (with grid) bass engine w/ keyboard+sequencer, looped/one-shot sample player

### controls

there are two modes - performance and editor. 

in performance mode:

- K1 switches to edit mode
- K2 switches parameters
- K3 stops/starts
- E1 changes volume
- E2 changes amen/track
- E3 changes break/punch

in edit mode:

- K1 switches to performance
- K2 select slice
- K3 auditions slice
- E1 changes kick
- E2 zooms
- E3 jogs slice

f*** it: 

- any two keys

## Grid

![image](https://user-images.githubusercontent.com/6550035/212520442-25b36eb9-f93e-42eb-9423-d02524ac45aa.png)


the **fx region** of the grid has the following effects in order, left-to-right and top to bottom: retrig, change volume, change pitch, delay, reverse, gate, tape stop, filter, mute

if you are using the sample player you can only sync them if they have `bpm` in the title. for example, `my_sound_bpm120.wav` will process it as a 120-bpm sample. upon loading, *amenbreak* stretches the sample to keep the same pitch but match the current tempo. *note*: this only works when loading, so be careful when using samples and changing tempo.

## Install

install with

```
;install https://github.com/schollz/amenbreak
```

https://github.com/schollz/amenbreak

