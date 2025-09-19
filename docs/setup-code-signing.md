# Code Signing Setup for FluidVoice Development

## Why Code Signing is Required

FluidVoice requires code signing for macOS TCC (Transparency, Consent, and Control) permissions to work properly. Without proper signing, the app cannot access microphone, accessibility features, or other protected resources.

## Setup Steps

### 1. Create Self-Signed Certificate

1. Open **Keychain Access** (Applications > Utilities > Keychain Access)
2. Go to **Keychain Access > Certificate Assistant > Create a Certificate...**
3. Configure certificate:
   - **Name**: `FluidVoice Development`
   - **Identity Type**: `Self Signed Root`
   - **Certificate Type**: `Code Signing`
   - Check **"Let me override defaults"**
4. Click **Continue** through the steps:
   - **Serial Number**: Accept default
   - **Validity Period**: Accept default (365 days)
   - **Email**: Use your email
   - **Name**: Accept defaults
   - **Key Pair Information**: Accept defaults (2048 bits, RSA)
   - **Key Usage Extension**: Check **"Certificate Signing"** (uncheck "Signature")
   - **Extended Key Usage Extension**: Check **"Code Signing"**
   - **Basic Constraints Extension**: Leave unchecked
5. **Keychain**: Select **login**
6. Click **Create**

### 2. Set Certificate Trust

1. In Keychain Access, find the "FluidVoice Development" certificate
2. Double-click the certificate
3. Expand **"Trust"** section
4. Set **"Code Signing"** to **"Always Trust"**
5. Close the window (enter password when prompted)

### 3. Configure Environment

1. Get your certificate hash:
   ```bash
   security find-identity -v -p codesigning
   ```

2. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

3. Update `.env` with your certificate hash:
   ```
   CODE_SIGN_IDENTITY="YOUR_CERTIFICATE_HASH_HERE"
   ```

### 4. Test

Run the development build:
```bash
./build-dev.sh
```

The build should now complete without code signing errors.

## Troubleshooting

- **"0 valid identities found"**: Certificate trust not set properly
- **"no identity found"**: Certificate not in login keychain
- **Permission errors**: Terminal may need microphone permission for TCC attribution

## Certificate Validity

Self-signed certificates expire after 365 days. When expired, repeat the certificate creation process with a new certificate.