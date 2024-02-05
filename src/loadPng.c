#include <loadPng.h>
#include <stdlib.h>
#include <stdio.h>
#include <png.h>

uint8_t*
loadPng(uint32_t* width, uint32_t* height)
{
	FILE* fp = fopen("assets/TextureMap.png", "rb");
	if (!fp)
		return 0;

	uint8_t sig[8];
	fread(sig, 1, 8, fp);
	if (png_sig_cmp(sig, 0, 8))
		return 0;

	png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, 0, 0, 0);
	if (!png_ptr)
		return 0;
	png_infop info = png_create_info_struct(png_ptr);
	if (!info)
		return 0;

	if (setjmp(png_jmpbuf(png_ptr)))
		goto cleanup;

	png_init_io(png_ptr, fp);
	png_set_sig_bytes(png_ptr, 8);
	png_read_info(png_ptr, info);

	int bit_depth, color_type;
	png_get_IHDR(png_ptr, info, width, height, &bit_depth, &color_type, 0, 0, 0);
	if (bit_depth == 16)
		png_set_strip_16(png_ptr);
	switch (color_type) {
	case PNG_COLOR_TYPE_PALETTE:
		png_set_expand(png_ptr);
		break;
	case PNG_COLOR_TYPE_GRAY_ALPHA:
		png_set_strip_alpha(png_ptr);
		/* FALLTHRU */
	case PNG_COLOR_TYPE_GRAY:
		if (bit_depth < 8)
			png_set_expand(png_ptr);
		png_set_gray_to_rgb(png_ptr);
		break;
	case PNG_COLOR_TYPE_RGB_ALPHA:
		png_set_strip_alpha(png_ptr);
		/* FALLTHRU */
	case PNG_COLOR_TYPE_RGB:
		break;
	default:
		goto cleanup;
	}

	double gamma;
	if (png_get_gAMA(png_ptr, info, &gamma))
		png_set_gamma(png_ptr, 2.2, gamma); // Choose better gamma

	png_read_update_info(png_ptr, info);

	if (png_get_channels(png_ptr, info) != 3)
		goto cleanup;
	png_uint_32 rowbytes = png_get_rowbytes(png_ptr, info);

	uint8_t** row_ptrs = malloc(*height * sizeof(png_bytep));
	if (!row_ptrs)
		goto cleanup;
	uint8_t* data = malloc(rowbytes * *height);
	if (!data) {
		free(row_ptrs);
		goto cleanup;
	}

	for (uint32_t i = 0; i < *height; ++i)
		row_ptrs[i] = data + i*rowbytes;
	png_read_image(png_ptr, row_ptrs);
	free(row_ptrs);
	row_ptrs = 0;
	png_read_end(png_ptr, 0);

cleanup:
	png_destroy_read_struct(&png_ptr, &info, 0);
	fclose(fp);
	return data;
}
