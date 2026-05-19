#include "Platform.h"
#include "AudioData.h"
#include <deque>
#include <commdlg.h>
#include "Tripex.h"
#include "RendererDirect3d.h"
#include "effect.h"
#include "AudioDevice.h"

static const int TICK_TIMER_ID = 0x1234;

static void HandleError(HWND hWnd, Error* error);

struct AppState
{
	ULONGLONG last_tick;
	std::shared_ptr<Tripex> tripex;
	std::shared_ptr<RendererDirect3d> renderer;
	std::shared_ptr<AudioDevice> audio_device;
	std::shared_ptr<AudioSource> audio_source;
};

Error* CreateWaveOutDevice(AppState& app, std::unique_ptr<AudioSource> new_audio_source)
{
	app.audio_device.reset();
	app.audio_source.reset();

	std::shared_ptr<WaveOutAudioDevice> device = std::make_shared<WaveOutAudioDevice>(std::move(new_audio_source));

	Error* error = device->Create();
	if (error != nullptr)
	{
		return error;
	}

	app.audio_device = device;
	app.audio_source = device;

	return nullptr;
}

LRESULT WndProc(HWND hWnd, uint32 nMsg, WPARAM wParam, LPARAM lParam)
{
	switch (nMsg)
	{
	case WM_CREATE:
		{
			AppState* app = new AppState();
			SetWindowLongPtr(hWnd, GWLP_USERDATA, (LONG_PTR)app);

			app->renderer = std::make_shared<RendererDirect3d>();
			app->audio_device.reset();
			app->audio_source = std::make_shared<RandomAudioSource>();

			Error* error = app->renderer->Open(hWnd);
			if (error)
			{
				HandleError(hWnd, error);
				return FALSE;
			}

			app->tripex = std::make_shared<Tripex>(app->renderer);

			error = app->tripex->Startup();
			if (error)
			{
				HandleError(hWnd, error);
				return FALSE;
			}

			SetTimer(hWnd, TICK_TIMER_ID, 10, nullptr);
		}
		return FALSE;
	case WM_TIMER:
		if (wParam == TICK_TIMER_ID)
		{
			AppState* app = (AppState*)GetWindowLongPtr(hWnd, GWLP_USERDATA);

			ULONGLONG this_tick = GetTickCount64();
			float elapsed = (this_tick - app->last_tick) / 1000.0f;
			app->last_tick = this_tick;

			if (app->audio_device)
			{
				app->audio_device->Tick(elapsed);
			}

			Error* error = app->tripex->Render(*app->audio_source);
			if (error)
			{
				HandleError(hWnd, error);
			}
		}
		break;
	case WM_DESTROY:
		{
			AppState* app = (AppState*)GetWindowLongPtr(hWnd, GWLP_USERDATA);
			KillTimer(hWnd, TICK_TIMER_ID);

			if (app->audio_device)
			{
				Error* error = app->audio_device->Destroy();
				if (error) HandleError(hWnd, error);

				app->audio_device.reset();
			}

			if (app->tripex)
			{
				app->tripex->Shutdown();
				app->tripex.reset();
			}

			if (app->renderer)
			{
				app->renderer->Close();
				app->renderer.reset();
			}

			delete app;
			SetWindowLongPtr(hWnd, GWLP_USERDATA, (LONG_PTR)0);
		}
		return FALSE;
	case WM_KEYDOWN:
		{
			AppState* app = (AppState*)GetWindowLongPtr(hWnd, GWLP_USERDATA);
			switch (wParam)
			{
			case VK_ESCAPE:
				DestroyWindow(hWnd);
				break;
			case VK_F1:
				app->tripex->ToggleHelp();
				break;
			case VK_F2:
				app->tripex->ToggleAudioInfo();
				break;
			case VK_LEFT:
				app->tripex->MoveToPrevEffect();
				break;
			case VK_RIGHT:
				app->tripex->MoveToNextEffect();
				break;
			case 'R':
				app->tripex->ReconfigureEffect();
				break;
			case 'E':
				app->tripex->ChangeEffect();
				break;
			case 'H':
				app->tripex->ToggleHoldingEffect();
				break;
			case 'M':
				app->audio_device.reset();
				app->audio_source = std::make_shared<RandomAudioSource>();
				break;
			case 'O':
				{
					char filename[MAX_PATH] = {};

					OPENFILENAMEA ofn = {};
					ofn.lStructSize = sizeof(ofn);
					ofn.hwndOwner = hWnd;
					ofn.lpstrFilter = "Wav files (*.wav)\0*.wav\0All files (*.*)\0*.*\0";
					ofn.lpstrFile = filename;
					ofn.nMaxFile = sizeof(filename);
					ofn.nFilterIndex = 1;
					ofn.lpstrFileTitle = NULL;
					ofn.nMaxFileTitle = 0;
					ofn.lpstrInitialDir = NULL;
					ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST;

					if (GetOpenFileNameA(&ofn))
					{
						std::unique_ptr<MemoryAudioSource> source;

						Error* error = MemoryAudioSource::CreateFromWavFile(filename, source);
						if (error != nullptr)
						{
							HandleError(hWnd, error);
							return FALSE;
						}

						error = CreateWaveOutDevice(*app, std::move(source));
						if (error != nullptr)
						{
							HandleError(hWnd, error);
							return FALSE;
						}
					}
				}
				break;
			case 'T':
				{
					int length = 20; // length in seconds
					int num_channels = 2;
					int sample_rate = 44100;

					size_t block_size = num_channels * sizeof(int16);
					size_t num_blocks = length * sample_rate;

					size_t buffer_size = num_blocks * block_size;
					std::unique_ptr<uint8[]> buffer = std::make_unique<uint8[]>(buffer_size);

					int16* next_sample = (int16*)buffer.get();
					for (int idx = 0; idx < num_blocks; idx++)
					{
						float time = (float)idx / sample_rate;
						float frequency = ((((int)time) % 2) == 0) ? 256.0f : 512.0f;
						float angle = time * frequency * PI2;

						int16 sample = (int16)(32760.0f * sinf(angle));
						*(next_sample++) = sample;
						*(next_sample++) = sample;
					}

					std::unique_ptr<MemoryAudioSource> source = std::make_unique<MemoryAudioSource>(std::move(buffer), buffer_size);

					Error* error = CreateWaveOutDevice(*app, std::move(source));
					if (error != nullptr)
					{
						HandleError(hWnd, error);
						return FALSE;
					}
				}
				break;
			}
		}
		return FALSE;
	}

	return DefWindowProc(hWnd, nMsg, wParam, lParam);
}

static void HandleError(HWND hWnd, Error* error)
{
	KillTimer(hWnd, TICK_TIMER_ID);
	MessageBoxA(hWnd, error->GetDescription().c_str(), nullptr, MB_OK);
	CloseWindow(hWnd);
}

int WINAPI WinMain(_In_ HINSTANCE hInstance, _In_opt_ HINSTANCE hPrevInstance, _In_ LPSTR sCmdLine, _In_ int nCmd)
{
	WNDCLASS wc;
	ZeroMemory(&wc, sizeof(wc));
	wc.hCursor = LoadCursor(0, IDC_ARROW);
	wc.lpszClassName = L"TripexWndClass";
	wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
	wc.hInstance = hInstance;
	wc.style = CS_VREDRAW | CS_HREDRAW;
	wc.lpfnWndProc = &WndProc;
	RegisterClass(&wc);

	HWND hWnd = CreateWindow(wc.lpszClassName, L"Tripex", WS_OVERLAPPEDWINDOW, 50, 50, 800, 600, nullptr, nullptr, hInstance, nullptr);
	ShowWindow(hWnd, SW_SHOW);
	UpdateWindow(hWnd);

	MSG msg;
	while (IsWindow(hWnd))
	{
		DWORD dwRes = GetMessage(&msg, nullptr, 0, 0);
		if (dwRes == 0 || dwRes == -1) break;

		TranslateMessage(&msg);
		DispatchMessage(&msg);
	}

	return 0;
}
