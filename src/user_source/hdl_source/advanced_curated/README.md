# Curated advanced RTL set

This is the first integration boundary for the advanced project. These files are selected lecture sources and are not yet connected to the existing top or TD project.

Selected groups:
- FAT32/storage: fat32_volume_scanner, fat32_file_streamer, SD SPI engines, media ingest wrappers.
- Four-bank/video: media_frame_reader, media_sdram_write_cdc, fifo_prefetch_2, media_player_control, media_video_pipeline, video_timing_ctrl, rgb_video_adapter.
- WAV/audio: wav_stream_player, audio_source_mux, pcm_content_mux, sync_fade_gain.
- FAT32 arbitration: fat32_sector_bridge latches one scan/file LBA per sector and
  prevents concurrent users from driving the official SD sector reader.

Do not add this directory wholesale to TD. The baseline has different top-level signal names and a different PLL/SDRAM interface. Adapt one subsystem at a time, add dependencies explicitly, and synthesize before continuing.

## FAT32 migration status

`sd_sector_adapter.v` is implemented for the baseline `sd_card_top` contract. `sd_card_bmp_fat32.v` is only an isolated copy of the original controller with a unique module name; it is not yet a FAT32 implementation. The lecture notes provide the scanner/streamer/adapter integration points and code fragments, but not a complete directly compilable replacement for this project. The remaining work is the sector arbiter, resource-to-cluster selection, BMP data-offset parser, BGR byte packer, and the existing SDRAM write handshake.

Do not add `sd_card_bmp_fat32.v` to the active TD design until those paths are implemented and checked.
