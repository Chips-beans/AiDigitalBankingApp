package com.bank.digital_banking.common.util;

import com.bank.digital_banking.common.exception.ApiException;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;

public final class PageBounds {
    private PageBounds() { }
    public static PageRequest ascendingId(int page, int size) {
        return of(page, size).withSort(org.springframework.data.domain.Sort.by("id"));
    }
    public static PageRequest descendingId(int page, int size) {
        return of(page, size).withSort(org.springframework.data.domain.Sort.by(org.springframework.data.domain.Sort.Direction.DESC, "id"));
    }
    public static PageRequest of(int page, int size) {
        if (page < 0 || size < 1 || size > 100 || (long) page * size > Integer.MAX_VALUE)
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_PAGINATION", "Page must be nonnegative and size must be between 1 and 100");
        return PageRequest.of(page, size);
    }
}
