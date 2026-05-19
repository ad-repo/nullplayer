#include "Platform.h"
#include "error.h"
#include "Texture.h"
#include "TextureFont.h"
#include "TextureData.h"
#include "AudioData.h"
#include <algorithm>
#include <assert.h>
#include "Tripex.h"

IMPORT_EFFECT(Blank);
IMPORT_EFFECT(BezierCube);
IMPORT_EFFECT(CollapsingLightSphere);
IMPORT_EFFECT(Distortion1);
IMPORT_EFFECT(Distortion2);
IMPORT_EFFECT(Distortion2Col);
IMPORT_EFFECT(DotStar);
IMPORT_EFFECT(Flowmap);
IMPORT_EFFECT(Tunnel);
IMPORT_EFFECT(WaterGlobe);
IMPORT_EFFECT(Tube);
IMPORT_EFFECT(Sun);
IMPORT_EFFECT(Bumpmapping);
IMPORT_EFFECT(Spectrum);
IMPORT_EFFECT(Rings);
IMPORT_EFFECT(Phased);
IMPORT_EFFECT(MotionBlur1);
IMPORT_EFFECT(MotionBlur2);
IMPORT_EFFECT(MotionBlur3);
IMPORT_EFFECT(MotionBlur3Alt);
IMPORT_EFFECT(MorphingSphere);
IMPORT_EFFECT(Metaballs);
IMPORT_EFFECT(LightTentacles);
IMPORT_EFFECT(LightStar);
IMPORT_EFFECT(LightSphere);
IMPORT_EFFECT(LightRing);

/****** constants *****/

Tripex::Tripex(std::shared_ptr<Renderer> renderer)
	: renderer(std::move(renderer))
{
	CreateEffects();
}

Tripex::~Tripex()
{
	texture_library.Reset();
}

void Tripex::ShowStatusMsg(const char* format, ...)
{
	va_list arg_list;
	va_start(arg_list, format);

	vsnprintf(status_msg, sizeof(status_msg), format, arg_list);
	status_time = GetSystemTimestampMs();

	va_end(arg_list);
}

Error* Tripex::Startup()
{
	txs.reset();

	enabled_effects.push_back(effects[0]);

	effect_frames = 0.0f;
	fade_pos = 0.0f;
	status_msg[0] = 0;
	status_time = 0;
	effect_idx = 0;
	next_effect_idx = 0;

	audio = std::make_unique<AudioData>(512);

	srand(GetSystemTimestampMs());

	std::vector<ColorRgb> pe;
	pe.resize(256);
	for (int i = 0; i < 256; i++)
	{
		pe[i] = ColorRgb(i, i, i);
	}

	//	{for( int i = 0; i < 256 * 256; i++ )
	//	{
	//		unsigned char c = ((uint8*)&g_anTexRawGUI[ 1 ])[ i ];
	//		pc[ i ] = ZColour( c,c,c);
	//	}
	//	}

	Error* error = renderer->CreateTexture(256, 256, TextureFormat::P8, &tex_raw_gui[1], 256 * 256, 256, pe.data(), TextureFlags::None, gui);
	if (error) return TraceError(error);

	//	gui = auto_ptr< ZTexture >(new ZTexture(pc));//(ZColour*)g_anTexRawGUI ));//cGUI.GetPtr()));
	//	gui->m_nFlags.set(ZTexture::F_POINT_FILTER);

		// TEXTURE
	//	renderer.AddTexture( gui.get( ) );
	//	g_pD3D->vpTexture.push_back(gui.get());//auto_ptr< ZTexture >(gui);

	tef.Add((uint8*)&tex_raw_font[1]);
	tef.FindGlyph(' ')->end = 2;

	error = tef.Create(*renderer);
	if (error) return TraceError(error);

	//	renderer.AddTexture( tef.GetTexture( ) );
	//	g_pD3D->vpTexture.push_back(tef.GetTexture());

	//	pcBuffer.SetLength(1024 * 16);

	//	pcHUD = new ZPaletteCanvas;
	//	pcHUD->Create(true, 1024, 16);
	//	ZColour c[256];
	//	for(int i = 0; i < 256; i++) c[i] = ZColour::Grey(i);
	//	pcHUD->SetPalette(c);

	srand(GetSystemTimestampMs());

	for (int i = 1; i < (int)effects.size(); i++)
	{
		if (effects[i]->preference > FLOAT_ZERO)
		{
			enabled_effects.push_back(effects[i]);
		}
	}

	srand(GetSystemTimestampMs());

	std::map<const uint32*, std::shared_ptr<Texture>> data_to_texture;

	for (const std::shared_ptr<Effect>& effect_handler : enabled_effects)
	{
		Effect& effect = *effect_handler.get();
		for (const TextureClass* texture_class : effect.textures)
		{
			for (const uint32* internal_texture : texture_class->internal_textures)
			{
				std::map<const uint32*, std::shared_ptr<Texture>>::const_iterator it = data_to_texture.find(internal_texture);
				if (it == data_to_texture.find(internal_texture))
				{
					std::shared_ptr<Texture> texture;

					if (internal_texture != tex_blank)
					{
						error = renderer->CreateTextureFromImage(internal_texture + 1, *internal_texture, texture);
						if (error != nullptr) return error;
					}

					it = data_to_texture.insert(std::make_pair(internal_texture, std::move(texture))).first;
				}
				texture_library.Add(*texture_class, it->second);
			}
		}
	}

	id = (int)enabled_effects.size();

	txs.set(TXS_CHANGE_EFFECT);

	txs.set(TXS_RESET_TIMING);

	txs.set(TXS_SHOW_HELP);

	return nullptr;
}

Error* Tripex::Render(AudioSource& audio_source)
{
	uint32 time = GetSystemTimestampMs();
	if (txs.test(TXS_RESET_TIMING))//bResetTiming)
	{
		last_time = time - 10000;
		txs.reset(TXS_RESET_TIMING);
	}

	uint32 dwTimeChange = time - last_time;
	float elapsed = dwTimeChange / 1000.0f;

	frames += std::min(4.0f, dwTimeChange / (1000.0f / 15.0f));
	last_time = time;

	effect_frames += frames;
	fade_pos += dwTimeChange;

	Effect* draw_effects[2];
	if (txs.test(TXS_EFFECT_LEFT) || txs.test(TXS_EFFECT_RIGHT))//bEffectLeft || bEffectRight))
	{
		int new_effect_idx = effect_idx;
		if (txs.test(TXS_EFFECT_LEFT))
		{
			if (effect_idx > 1) new_effect_idx--;
			txs.reset(TXS_EFFECT_LEFT);
		}
		else
		{
			if (effect_idx < (int)enabled_effects.size() - 1) new_effect_idx++;
			txs.reset(TXS_EFFECT_RIGHT);
		}

		if (new_effect_idx != effect_idx)
		{
			effect_idx = new_effect_idx;
			ShowStatusMsg("Current Effect: %s", enabled_effects[effect_idx]->name.c_str());

			txs.reset(TXS_IN_FADE);
			effect_frames = 0;

			Effect::ReconfigureParams params(*audio.get(), texture_library);

			Error* error = enabled_effects[effect_idx]->Reconfigure(params);
			if (error) return TraceError(error);
		}
	}

	const float EFFECT_CHANGE_FRAMES = 400.0f;
	if (!txs.test(TXS_IN_FADE) && (!txs.test(TXS_HOLD) || txs.test(TXS_CHANGE_EFFECT)) &&
		(effect_idx == 0 ||
			effect_frames > (enabled_effects[effect_idx]->change * EFFECT_CHANGE_FRAMES)) &&
		enabled_effects.size() > 1)
	{
		txs.reset(TXS_CHANGE_EFFECT);
		next_effect_idx = 0;

		txs.set(TXS_IN_FADE);
		effect_frames = 0;

		for (int i = 1; i < (int)enabled_effects.size(); i++)
		{
			enabled_effects[i]->bValid = (i != effect_idx && enabled_effects[effect_idx]->draw_order != enabled_effects[i]->draw_order);
		}

		float pt = 0;
		// fairness = (random)0-1(ordered)
		const float selection_fairness = 0.7f;
		float temperature = (1.0f / selection_fairness) - 1;
		// temperature = (random)+inf - 0(ordered)
		for (int i = 1; i < (int)enabled_effects.size(); i++)
		{
			float weight = (float(id - enabled_effects[i]->nLastUsed) / (enabled_effects.size() - 1)) - 1;
			// weight = small (last used) - large (not used)

			if (!enabled_effects[i]->bValid)
			{
				enabled_effects[i]->fProb = 0.0f;
			}
			else if (temperature < FLOAT_ZERO)
			{
				enabled_effects[i]->fProb = (weight >= 0) ? 0.5f : 0.0f;
			}
			else
			{
				enabled_effects[i]->fProb = 1.0f / (1.0f + expf(-weight / temperature));
			}

			enabled_effects[i]->fProb *= enabled_effects[i]->preference * std::max(0.1f, 1.0f - fabsf(audio->GetIntensity() - enabled_effects[i]->activity));

			pt += enabled_effects[i]->fProb;//vpEffect[i]->preference * p[i];
		}

		next_effect_idx = 0;
		if (pt > FLOAT_ZERO)
		{
			for (int i = 1; i < (int)enabled_effects.size(); i++)
			{
				enabled_effects[i]->fProb /= pt;
			}

			double r = (rand() % 1000);
			for (next_effect_idx = 1; next_effect_idx < (int)enabled_effects.size() - 1; next_effect_idx++)
			{
				r -= enabled_effects[next_effect_idx]->fProb * 1000.0;
				if (r < 0) break;
			}
		}
		enabled_effects[next_effect_idx]->nLastUsed = id;

		fade_pos = 0;
		txs.reset(TXS_RESET_TARGET);
	}
	if (txs[TXS_RECONFIGURE])//bReconfigure)
	{
		Effect::ReconfigureParams params(*audio.get(), texture_library);

		Error* error = enabled_effects[effect_idx]->Reconfigure(params);
		if (error) return TraceError(error);

		txs.reset(TXS_IN_FADE);
		txs.reset(TXS_RECONFIGURE);
	}

	if (txs.test(TXS_HOLD))//bEffectPref)
	{
		txs[TXS_IN_FADE] = false;
		if (effect_idx == 0) effect_idx = next_effect_idx;
	}

	const float cross_fading = 0.934f;
	const float fade_in = 0.241f;
	const float fade_out = 0.353f;

	float out = (effect_idx == 0) ? 0 : (fade_out * 5000.0f);
	float fade_length = (fade_in * 5000.0f) + out - (cross_fading * std::min((fade_in * 5000.0f), out));

	float br = txs.test(TXS_IN_FADE) ? std::min(1.0f, std::max(0.0f, 1.0f - (fade_pos / out))) : 1;
	draw_effects[0] = (br < FLOAT_ZERO) ? blank_effect : enabled_effects[effect_idx].get();
	draw_effects[0]->fBr = br;

	br = txs.test(TXS_IN_FADE) ? std::min(1.0f, std::max(0.0f, 1.0f - ((fade_length - fade_pos) / (fade_in * 5000.0f)))) : 0;
	draw_effects[1] = (br < FLOAT_ZERO) ? blank_effect : enabled_effects[next_effect_idx].get();
	draw_effects[1]->fBr = br;

	if (draw_effects[1]->fBr > FLOAT_ZERO && !txs[TXS_RESET_TARGET])
	{
		Effect::ReconfigureParams params(*audio.get(), texture_library);

		Error* error = draw_effects[1]->Reconfigure(params);
		if (error) return TraceError(error);

		txs[TXS_RESET_TARGET] = true;
	}
	if (draw_effects[1]->fBr >= 1 - FLOAT_ZERO)
	{
		effect_idx = next_effect_idx;
		draw_effects[0] = draw_effects[1];
		draw_effects[1] = blank_effect;//&blank;
		txs.reset(TXS_IN_FADE);
	}

	if (draw_effects[1]->draw_order < draw_effects[0]->draw_order)
	{
		std::swap(draw_effects[1], draw_effects[0]);
	}
	if ((!draw_effects[0]->CanRender(frames) || draw_effects[0] == blank_effect) && (!draw_effects[1]->CanRender(frames) || draw_effects[1] == blank_effect) && !(draw_effects[0] == blank_effect && draw_effects[1] == blank_effect && frames > 1.0f))
	{
		return nullptr;
	}

	audio->Update(elapsed, enabled_effects[effect_idx]->sensitivity, audio_source);

	for (int i = 0; i < 2; i++)
	{
		audio->SetIntensityBeatScale(draw_effects[i]->sensitivity * 3.0f);

		Effect::CalculateParams params(draw_effects[i]->fBr, draw_effects[i]->GetElapsed(frames), *audio.get(), *renderer);

		Error* error = draw_effects[i]->Calculate(params);
		if (error) return TraceError(error);

		audio->SetIntensityBeatScale(0.0f);
	}

	Error* error = renderer->BeginFrame();
	if (error) return TraceError(error);

	for (int i = 0; i < 2; i++)
	{
		error = draw_effects[i]->Render(*renderer);
		if (error) return TraceError(error);
	}

	overlay_background.Clear();
	overlay_text.Clear();
	overlay_foreground.Clear();

	std::string msg;
	float msg_brightness = 0.0f;

	uint32 dwTick = GetSystemTimestampMs();
	if (dwTick >= status_time && dwTick <= status_time + (MSG_DISPLAY_TIME + MSG_FADEOUT_TIME) && status_msg[0] != 0)
	{
		msg = status_msg;
		if (dwTick < status_time + MSG_DISPLAY_TIME) msg_brightness = 1.0f;
		else
		{
			float fPos = (dwTick - (status_time + MSG_DISPLAY_TIME)) / (float)MSG_FADEOUT_TIME;
			float fV = 1.0f - cos(fPos * 3.14159f / 2.0f);
			msg_brightness = 1.0f - (fV * fV);//fPos;//fV;//1 - (fV * fV);//1.0f;
		}
	}

	const float overlay_back_mult = 0.65f;

	if (msg.size() > 0)
	{
		DrawMessage(tef, 38, msg.c_str(), msg_brightness, overlay_back_mult);
	}

	if (txs.test(TXS_VISIBLE_BEATS))
	{
		audio->Render(overlay_background, overlay_foreground, overlay_back_mult);
	}

	if (txs.test(TXS_SHOW_HELP))
	{
		static const char* help_text[][2] =
		{
			{ "F1", "Toggle this help window" },
			{ "F2", "Show audio info" },
			{ "<", "Previous effect" },
			{ ">", "Next effect" },
			{ "R", "Reconfigure current effect" },
			{ "E", "Choose random effect" },
			{ "H", "Hold current effect" },
			{ "O", "Open a WAV file for playback" },
			{ "T", "Play a test tone" },
			{ "M", "Mute audio (use random data)" }
		};

		int num_lines = sizeof(help_text) / sizeof(help_text[0]);

		int margin_x = 40;
		int margin_y = 15;
		int col1_w = 100;
		int col2_w = 250;
		int line_height = 20;

		int w = (margin_x * 2) + col1_w + col2_w;
		int h = (margin_y * 2) + (line_height * num_lines);
		int x = (renderer->GetWidth() - w) / 2;
		int y = (renderer->GetHeight() - h) / 2;

		overlay_background.AddSprite(Point<int>(x, y), Rect<int>(0, 0, w, h), overlay_back_mult);

		for (int line_idx = 0; line_idx < num_lines; line_idx++)
		{
			int line_y = y + margin_y + (line_height * line_idx);
			tef.Draw(overlay_text, help_text[line_idx][0], Point<int>(x + margin_x + 10 - tef.GetWidth(help_text[line_idx][0]) / 2, line_y), ColorRgb::Grey(192.0f));
			tef.Draw(overlay_text, help_text[line_idx][1], Point<int>(x + margin_x + col1_w, line_y), ColorRgb::Grey(192.0f));
		}
	}

	// Draw the overlay background
	{
		RenderState render_state;
		render_state.blend_mode = BlendMode::OverlayBackground;
		render_state.depth_mode = DepthMode::Disable;

		error = renderer->DrawIndexedPrimitive(render_state, overlay_background);
		if (error) return TraceError(error);
	}

	// Draw the overlay text
	{
		RenderState render_state;
		render_state.blend_mode = BlendMode::OverlayForeground;
		render_state.depth_mode = DepthMode::Disable;
		render_state.texture_stages[0].texture = tef.texture.get();

		error = renderer->DrawIndexedPrimitive(render_state, overlay_text);
		if (error) return TraceError(error);
	}

	// Draw the overlay foreground
	{
		RenderState render_state;
		render_state.blend_mode = BlendMode::OverlayForeground;
		render_state.depth_mode = DepthMode::Disable;

		error = renderer->DrawIndexedPrimitive(render_state, overlay_foreground);
		if (error) return TraceError(error);
	}

	error = renderer->EndFrame();
	if (error) return TraceError(error);

	frames = 0;
	return 0;
}
void Tripex::Shutdown()
{
	audio.reset();

	enabled_effects.clear();
	effects.clear();
}

void Tripex::ChangeEffect()
{
	txs[TXS_CHANGE_EFFECT] = true;
}

void Tripex::MoveToPrevEffect()
{
	txs[TXS_EFFECT_LEFT] = true;
}

void Tripex::MoveToNextEffect()
{
	txs[TXS_EFFECT_RIGHT] = true;
}

void Tripex::ReconfigureEffect()
{
	txs[TXS_RECONFIGURE] = true;
}

void Tripex::ToggleHoldingEffect()
{
	txs.flip(TXS_HOLD);
	ShowStatusMsg("Effect %s", txs[TXS_HOLD] ? "held" : "not held");
}

void Tripex::ToggleAudioInfo()
{
	txs.flip(TXS_VISIBLE_BEATS);
}

void Tripex::ToggleHelp()
{
	txs.flip(TXS_SHOW_HELP);
}

int Tripex::GetClippedLineLength(const TextureFont& font, const char* text, int clip_width)
{
	bool is_first_word = true;
	int last_end = 0;
	for (int i = 0;;)
	{
		bool space = (isspace(text[i]) != 0);
		if (space || text[i] == 0 || is_first_word)
		{
			if (space) is_first_word = false;

			std::string line = std::string(text, i);
			if (font.GetWidth(line.c_str()) > clip_width)
			{
				return last_end;
			}
			else if (text[i] == 0)
			{
				return i;
			}

			last_end = i;

			if (space)
			{
				while (isspace(text[i])) i++;
			}
			else i++;
		}
		else i++;
	}
}

void Tripex::DrawMessage(const TextureFont& font, int y, const char* text, float brightness, float back_brightness)
{
	const int clip_width = renderer->GetWidth() - 40;
	const int line_height = 20;

	std::vector<std::string> lines;
	int width = 0;
	for (;;)
	{
		while (isspace(*text))
		{
			text++;
		}
		if (*text == 0)
		{
			break;
		}

		int length = GetClippedLineLength(font, text, clip_width);
		if (length > 0)
		{
			std::string line(text, length);
			lines.push_back(line);
			width = std::max(width, font.GetWidth(line.c_str()));
			text += length;
		}
	}

	int centre_x = renderer->GetWidth() / 2;

	if (back_brightness > FLOAT_ZERO)
	{
		float dark_brightness = (back_brightness * brightness);
		const Point<int> p(centre_x - (width / 2) - 15, y);
		const Rect<int> r(0, 0, width + 30, 25 + ((int)lines.size() - 1) * line_height);
		overlay_background.AddSprite(p, r, dark_brightness);
	}

	for (int i = 0; i < (int)lines.size(); i++)
	{
		int line_width = font.GetWidth(lines[i].c_str());
		font.Draw(overlay_text, lines[i].c_str(), Point<int>(centre_x - (line_width / 2), y + 5 + (i * line_height)), ColorRgb::Grey((int)(brightness * 255.0f)));
	}
}

void Tripex::AddEffect(std::shared_ptr<Effect>(*fn)(), const char* name, int draw_order, float startup_weight, int preference, int change, int sensitivity, int activity, int speed)
{
	std::shared_ptr<Effect> effect = fn();
	effect->name = name;
	effect->draw_order = draw_order;
	effect->startup_weight = startup_weight;

	effect->preference = preference / 1000.0f;
	effect->change = change / 1000.0f;
	effect->sensitivity = sensitivity / 1000.0f;
	effect->activity = activity / 1000.0f;
	effect->speed = speed / 1000.0f;

	if (effects.size() == 0)
	{
		effects.push_back(effect);
	}
	else
	{
		for (int i = 1;; i++)
		{
			if (i == effects.size() || _stricmp(effect->name.c_str(), effects[i]->name.c_str()) < 0)
			{
				effects.insert(effects.begin() + i, effect);
				break;
			}
		}
	}
}

void Tripex::CreateEffects()
{
	AddEffect(&CreateEffect_Blank, "Blank", ZORDER_BLANK, 1.0f, 0, 0, 0, 0, 0);

	blank_effect = effects[0].get();

	AddEffect(&CreateEffect_Tunnel, "Tunnel", ZORDER_TUNNEL, 1.0f, 750, 750, 840, 620, 560);
	AddEffect(&CreateEffect_WaterGlobe, "WaterGlobe", ZORDER_WATERGLOBE, 10.0f, 100, 200, 260, 390, 500);
	AddEffect(&CreateEffect_Tube, "Tube", ZORDER_TUBE, 1.0f, 230, 310, 450, 500, 480);
	AddEffect(&CreateEffect_Sun, "Sun", ZORDER_SUN, 1.0f, 80, 70, 280, 390, 500);
	AddEffect(&CreateEffect_Bumpmapping, "Bumpmapping", ZORDER_BUMPMAPPING, 8.0f, 800, 500, 900, 500, 570);
	AddEffect(&CreateEffect_Spectrum, "Spectrum", ZORDER_ANALYSER, 1.0f, 880, 660, 510, 510, 510);
	AddEffect(&CreateEffect_Rings, "ConcentricRings", ZORDER_RINGS, 1.0f, 660, 250, 590, 1000, 1000);
	AddEffect(&CreateEffect_Phased, "Phased", ZORDER_PHASED, 1.0f, 60, 100, 300, 270, 480);
	AddEffect(&CreateEffect_MotionBlur1, "MotionBlur1", ZORDER_MOTIONBLUR, 1.0f, 120, 80, 100, 490, 490);
	AddEffect(&CreateEffect_MotionBlur2, "MotionBlur2", ZORDER_MOTIONBLUR2, 1.0f, 50, 110, 940, 500, 450);
	AddEffect(&CreateEffect_MotionBlur3, "MotionBlur3", ZORDER_MOTIONBLUR3, 1.0f, 420, 370, 590, 490, 940);
	AddEffect(&CreateEffect_MotionBlur3Alt, "MotionBlur3(Alt)", ZORDER_MOTIONBLUR3ALT, 1.0f, 1000, 600, 580, 790, 840);
	AddEffect(&CreateEffect_MorphingSphere, "MorphingSphere", ZORDER_MORPHINGSPHERE, 1.0f, 400, 170, 850, 590, 500);
	AddEffect(&CreateEffect_LightTentacles, "LightTentacles", ZORDER_LIGHTTENTACLES, 1.0f, 410, 560, 660, 610, 460);
	AddEffect(&CreateEffect_LightStar, "LightStar", ZORDER_LIGHTSTAR, 1.0f, 60, 60, 500, 500, 570);
	AddEffect(&CreateEffect_LightSphere, "LightSphere", ZORDER_LIGHTSPHERE, 1.0f, 470, 370, 340, 420, 500);
	AddEffect(&CreateEffect_LightRing, "LightRing", ZORDER_LIGHTRING, 1.0f, 340, 420, 880, 690, 460);
	AddEffect(&CreateEffect_Flowmap, "Flowmap", ZORDER_FLOWMAP, 10.0f, 920, 800, 690, 580, 520);
	AddEffect(&CreateEffect_DotStar, "DotStar", ZORDER_DOTSTAR, 1.0f, 90, 280, 310, 390, 1000);
	AddEffect(&CreateEffect_Distortion2, "Distortion2", ZORDER_DISTORTION2, 1.0f, 550, 320, 500, 500, 460);
	AddEffect(&CreateEffect_Distortion2Col, "Distortion2(Lit)", ZORDER_DISTORTION2COL, 1.0f, 550, 320, 500, 500, 460);
	AddEffect(&CreateEffect_CollapsingLightSphere, "CollapsingLightSphere", ZORDER_COLLAPSINGSPHERE, 1.0f, 180, 280, 500, 310, 500);
	AddEffect(&CreateEffect_BezierCube, "BezierCube", ZORDER_BEZIERCUBE, 1.0f, 140, 40, 140, 480, 70);
	AddEffect(&CreateEffect_Distortion1, "Distortion1", ZORDER_DISTORTION, 1.0f, 210, 80, 640, 260, 520);
}
