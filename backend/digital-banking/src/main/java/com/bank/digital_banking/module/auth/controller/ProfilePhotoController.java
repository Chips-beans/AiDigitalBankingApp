package com.bank.digital_banking.module.auth.controller;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.service.ProfilePhotoService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import jakarta.servlet.http.HttpServletResponse;

@RestController @RequestMapping("/api/v1/auth/profile/photo") @RequiredArgsConstructor
public class ProfilePhotoController {
    private final ProfilePhotoService photos;

    @ModelAttribute
    public void noStore(HttpServletResponse response) {
        response.setHeader("Cache-Control", "private, no-store");
        response.setHeader("Pragma", "no-cache");
    }

    @GetMapping
    public ApiResponse<ProfilePhotoService.Photo> read(@AuthenticationPrincipal User user) {
        return ApiResponse.success(photos.read(user), "Profile photo");
    }

    @PutMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ApiResponse<ProfilePhotoService.Photo> save(@AuthenticationPrincipal User user, @RequestPart("photo") MultipartFile photo) {
        return ApiResponse.success(photos.save(user, photo), "Profile photo saved");
    }
}
