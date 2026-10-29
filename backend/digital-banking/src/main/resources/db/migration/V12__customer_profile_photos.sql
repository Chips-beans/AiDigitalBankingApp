-- One private, normalized photo per verified customer; no changes to banking data.
CREATE TABLE customer_profile_photos (
    user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    content_type VARCHAR(16) NOT NULL CHECK (content_type IN ('image/jpeg', 'image/png')),
    image_data BYTEA NOT NULL CHECK (octet_length(image_data) BETWEEN 1 AND 5242880),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);
