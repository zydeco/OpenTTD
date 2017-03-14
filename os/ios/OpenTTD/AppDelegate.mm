//
//  AppDelegate.mm
//  OpenTTD
//
//  Created by Jesús A. Álvarez on 28/02/2017.
//  Copyright © 2017 OpenTTD. All rights reserved.
//

#import "AppDelegate.h"
#include "stdafx.h"
#include "openttd.h"
#include "debug.h"
#include "cocoa_touch_v.h"
#include "factory.hpp"
#include "gfx_func.h"
#include "random_func.hpp"
#include "network.h"
#include "settings_type.h"
#include "settings_func.h"
#include "fontcache.h"
#include "window_func.h"
#include "window_gui.h"

static unsigned int _current_mods;
static bool _tab_is_down;
#ifdef _DEBUG
static uint32 _tEvent;
#endif

static uint32 GetTick()
{
	return CFAbsoluteTimeGetCurrent() * 1000;
}

static void CheckPaletteAnim()
{
	if (_cur_palette.count_dirty != 0) {
		Blitter *blitter = BlitterFactory::GetCurrentBlitter();
		
		switch (blitter->UsePaletteAnimation()) {
			case Blitter::PALETTE_ANIMATION_VIDEO_BACKEND:
				_cocoa_touch_driver->UpdatePalette(_cur_palette.first_dirty, _cur_palette.count_dirty);
				break;
				
			case Blitter::PALETTE_ANIMATION_BLITTER:
				blitter->PaletteAnimate(_cur_palette);
				break;
				
			case Blitter::PALETTE_ANIMATION_NONE:
				break;
				
			default:
				NOT_REACHED();
		}
		_cur_palette.count_dirty = 0;
	}
}

@interface AppDelegate ()

@end

@implementation AppDelegate
{
	NSTimer *gameLoopTimer;
	uint32 cur_ticks, last_cur_ticks, next_tick;
}

+ (AppDelegate *)sharedInstance {
	static AppDelegate *appDelegate;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		appDelegate = (AppDelegate*)[UIApplication sharedApplication].delegate;
	});
	return appDelegate;
}

- (void)setFontSetting:(FreeTypeSubSetting*)setting toFont:(UIFont*)font scale:(CGFloat)scale {
	strcpy(setting->font, font.fontDescriptor.postscriptName.UTF8String);
	setting->aa = true;
	setting->size = (uint)(font.pointSize * scale);
}

- (void)overrideDefaultSettings {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	IConsoleSetSetting("hover_delay_ms", 0);
	IConsoleSetSetting("osk_activation", 3);
	BOOL hiDPI = [defaults boolForKey:@"NativeResolution"];
	_gui_zoom = hiDPI ? 1 : 2;
	CGFloat fontScale = hiDPI ? [UIScreen mainScreen].nativeScale : 1.0;
	
	UIFont *smallFont = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
	[self setFontSetting:&_freetype.small toFont:smallFont scale:fontScale];
	[self setFontSetting:&_freetype.medium toFont:[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote] scale:fontScale];
	[self setFontSetting:&_freetype.large toFont:[UIFont preferredFontForTextStyle:UIFontTextStyleBody] scale:fontScale];
	[self setFontSetting:&_freetype.mono toFont:[UIFont fontWithName:@"Menlo-Bold" size:smallFont.pointSize] scale:fontScale];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	[self overrideDefaultSettings];
	
	GfxInitPalettes();
	CheckPaletteAnim();
	_cocoa_touch_driver->Draw();
	
	[self startGameLoop];
    return YES;
}

- (void)startGameLoop {
	if (gameLoopTimer.valid) return;
	cur_ticks = GetTick();
	last_cur_ticks = cur_ticks;
	next_tick = cur_ticks + MILLISECONDS_PER_TICK;
	NSTimeInterval gameLoopInterval = 1.0 / 60.0;
	gameLoopTimer = [NSTimer scheduledTimerWithTimeInterval:gameLoopInterval target:self selector:@selector(tick:) userInfo:nil repeats:YES];
}

- (void)stopGameLoop {
	[gameLoopTimer invalidate];
}

- (void)resizeGameView:(CGSize)size {
	CGFloat scale = [[NSUserDefaults standardUserDefaults] boolForKey:@"NativeResolution"] ? [UIScreen mainScreen].nativeScale : 1.0;
	_resolutions[0].width = size.width * scale;
	_resolutions[0].height = size.height * scale;
	_cocoa_touch_driver->ChangeResolution(size.width * scale, size.height * scale);
}

- (void)applicationWillResignActive:(UIApplication *)application {
	[self stopGameLoop];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
	//DoExitSave();
}


- (void)applicationWillEnterForeground:(UIApplication *)application {

}

- (void)applicationDidBecomeActive:(UIApplication *)application {
	[self startGameLoop];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)tick:(NSTimer*)timer {
	uint32 prev_cur_ticks = cur_ticks; // to check for wrapping
	InteractiveRandom(); // randomness
	
	if (_exit_game) {
		[timer invalidate];
		_cocoa_touch_driver->ExitMainLoop();
	}
	
#if defined(_DEBUG)
	if (_current_mods & NSShiftKeyMask)
#else
		if (_tab_is_down)
#endif
		{
			if (!_networking && _game_mode != GM_MENU) _fast_forward |= 2;
		} else if (_fast_forward & 2) {
			_fast_forward = 0;
		}
	
	cur_ticks = GetTick();
	if (cur_ticks >= next_tick || (_fast_forward && !_pause_mode) || cur_ticks < prev_cur_ticks) {
		_realtime_tick += cur_ticks - last_cur_ticks;
		last_cur_ticks = cur_ticks;
		next_tick = cur_ticks + MILLISECONDS_PER_TICK;
		
		bool old_ctrl_pressed = _ctrl_pressed;
		
		//_ctrl_pressed = !!(_current_mods & ( _settings_client.gui.right_mouse_btn_emulation != RMBE_CONTROL ? NSControlKeyMask : NSCommandKeyMask));
		//_shift_pressed = !!(_current_mods & NSShiftKeyMask);
		
		if (old_ctrl_pressed != _ctrl_pressed) HandleCtrlChanged();
		
		GameLoop();
		
		UpdateWindows();
		CheckPaletteAnim();
		_cocoa_touch_driver->Draw();
	}
}

@end
