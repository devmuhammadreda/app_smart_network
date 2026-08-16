// Self-signed fixture certificates and their SPKI pins.
//
// Regenerate with:
//   openssl req -x509 -newkey rsa:2048 -keyout k.pem -out c.pem -days 3650 \
//     -nodes -subj "/CN=api.example.com"
//
// The pins below are the output of the exact command documented in README.md,
// so they are ground truth from OpenSSL rather than from this package:
//   openssl x509 -in c.pem -pubkey -noout \
//     | openssl pkey -pubin -outform der \
//     | openssl dgst -sha256 -binary \
//     | openssl enc -base64
import 'dart:convert';
import 'dart:typed_data';

/// Leaf certificate for `CN=api.example.com`.
final Uint8List kPrimaryCertDer = base64.decode(
  'MIICsDCCAZgCCQC2CoVwsBwqFDANBgkqhkiG9w0BAQsFADAaMRgwFgYDVQQDDA9hcGkuZXhh'
  'bXBsZS5jb20wHhcNMjYwODE2MDkzODAyWhcNMzYwODEzMDkzODAyWjAaMRgwFgYDVQQDDA9h'
  'cGkuZXhhbXBsZS5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDPdX7WlBPo'
  'YCuF46633qqXjFyOyNoyvY7Zgon0ZUZBsouxWpb2j/RYgy9nwvQicBez6C+pRgKWp4/X6OCI'
  'h+aX0tatk5qJXgXRt0pyFSkxOyIwvWrYx0KjtFEtJIuUU3yYyei9kAIYxn4KC3RD2FH9glqD'
  'ywFNyRJyfCLNt8tdHufPNa28LXkV1wm19kz/DryKU3MiH1E5U2+Tb7hkkwy2LeHAE0nuH7Zj'
  'nNNtWxwq2WDnKMdz+3TxYW1Kr6p8NJrq2TjD3vwwE9N/NWE/1QhDyvrY16jGkXttC9kO85VL'
  '4YLBt2mB22Zue57PfsTqlaCS0mU9SMOOnwfI7znzrKaRAgMBAAEwDQYJKoZIhvcNAQELBQAD'
  'ggEBAIGsBLCRf8Ay+dk4R7/gXWizn/pXnu9xwHbVn9BNFLICC7qovuSsQQW9FUq6wwoPq4Pb'
  'wseDzU+e1yBvnYfTHkFNaHn1287xoi1ySnXfIPrFNo8Z0wEMh9R5fVDQ7DXjlCYqe6OUjMJa'
  'oQ+ZgzG4fcrzMPce+7YPnjK4Qxps+8+nnqWUv55JOzkndlpiAOSwVXWU/Hfzken6w6GP4BKt'
  'dbd2DhP1glsZBD9BIA0Gl+u2Bb0bJ2o5V4M4ux+kmgVcvggRvU5yITuuavv4tarb5tL2iNa8'
  'EdUwv9BToSslCw5N4DTJJKoHcUwvj4g6yxxXQ/TUb5UFieKe0Z+HQc6iByE=',
);

/// OpenSSL-computed SPKI pin for [kPrimaryCertDer].
const String kPrimaryPin =
    'sha256/U1lYtAEMYq6Unbc802/QoAWjlMzc9sv4z+5DbEInlEI=';

/// Leaf certificate for `CN=backup.example.com`, a different key pair.
final Uint8List kBackupCertDer = base64.decode(
  'MIICtjCCAZ4CCQC0XowYn78urDANBgkqhkiG9w0BAQsFADAdMRswGQYDVQQDDBJiYWNrdXAu'
  'ZXhhbXBsZS5jb20wHhcNMjYwODE2MDkzODAyWhcNMzYwODEzMDkzODAyWjAdMRswGQYDVQQD'
  'DBJiYWNrdXAuZXhhbXBsZS5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDl'
  'AUUSW6CbaOWKLngcgnARCE8L9/M8xfo0HTOAKNhzefvjtE5zimIMFA7Mew8ngh0uaZVndgT7'
  'OOzPfJ75okX7XulkO0lSNMUUynxtnA6PFWesg7hEWjcuVFu7HeuojH/CBZ8VgrbGB1Yu8k0r'
  'bYOPmQJ0dA98IBxTdYSA3e8SAh3GnQAtyRm8PRJufB1ABySsWk0tVPab0WTdrznXxNmXQUxl'
  'lumz4t11lSVY+gI+3uUz0eu3mmHbdqFmVNMpRefUo8OJyM5sxYY3jQH1iyJCGV7oXkHHjPb5'
  'ofE0LFrRECzwVvMfoI2sNXR7saKEHonLTzTO2l5wv+3owRQrnbtnAgMBAAEwDQYJKoZIhvcN'
  'AQELBQADggEBAN2X2oHTnzBEZxSannzE6pqMGqoMkP20se2g+on5G2aBaAev6yv8UeTZCQEg'
  'Hvqja3+YEH2Voy/xf1hbi0DQjoHkM3x9bspfCNFgmW4l7sQD2pcoeCy9EhZnXzbCioO3CyHN'
  'PgEEd9f74u3SprvZ+UV6B/PMFVwQQSfjBINsrQ3m+B4qj3nvytHjQg7Ra1eA48jCSd+TuB3O'
  'lnj8qbAak0/eijzy9XgOWDC49Tus9FYeIdjvfxkQ5PWVdKIsMRMOuXahtLKSgcsrsgGsAIsU'
  '32ZipJedDCJUXiGMuCZv+WbSHWp/Z2qbWG0J+IcuN0xSY9ZAGq/OOmcotPRuQ59VbjI=',
);

/// OpenSSL-computed SPKI pin for [kBackupCertDer].
const String kBackupPin = 'sha256/0QUH7apNYrGfDUVuwaNqWhFUhcpXXhpK2VtczeICUIY=';

/// Leaf certificate for `CN=rogue.example.org`, a third distinct key pair.
///
/// Stands in for a certificate an attacker might present: valid ASN.1, but
/// matching none of the pins under test.
final Uint8List kRogueCertDer = base64.decode(
  'MIICtDCCAZwCCQC9LjsbxxZO5DANBgkqhkiG9w0BAQsFADAcMRowGAYDVQQDDBFyb2d1ZS5l'
  'eGFtcGxlLm9yZzAeFw0yNjA4MTYwOTQ1MzdaFw0zNjA4MTMwOTQ1MzdaMBwxGjAYBgNVBAMM'
  'EXJvZ3VlLmV4YW1wbGUub3JnMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyzLo'
  'O8cO9eu1ej6pSQJvaFyG2tpnUHvaPUcnCnHpIn6ExmyPHuNYSI46Orp4WkLouTH4fsvA/Bix'
  '5DjJl4mN2jDCTfcUxoKiLkPKQEne5vRGFHupnRLfzAoT9VIvOyjqnFwmW/RjQWAo7uBrjRWW'
  'Rq9JsSN6ZB98oi0kFLoa3pUo9Igqtav5nfD9bSvsS9t/1gN0WiEyWn2ZHZSKEQLZSHsxFN81'
  'j1C8XHzs7VWrWPO+juswNcgJ3GFN9cHOgUkBV7PlMRqJ560NO3jca3L2whHi1g1UHyj/gau5'
  'U7i7Cls3/b6UZg21WWOrMxfUOhXkcRoWsJDRb5ODZaaLbt4DNQIDAQABMA0GCSqGSIb3DQEB'
  'CwUAA4IBAQBq+kcA57fIHkCoTO91fQDEC85K8k5INZNOF1lvz0iqXRe5nhBTKkRFUeGP42zR'
  '/4Duq893kHskmHpQAk8pAzljNLnKOJDt4yHjL3xX4UGkCIK92zMAcFsuhaBLxN6LJOMp37yE'
  '2RayISqbM7Ghdze5rS8+H7ndgAbcpPvwrJhVvg5s3J/vGQtp2eej/Ym8T3cirZxtQ3lL9VpA'
  'IDCPLg8z0clM8D0ylBvLYfsH642bg+mn92R6C/M1t0Bnw6R8bhVBtJR5n0ku2IuSTMuYv+Fk'
  'R3oNZogj8QSCopbImg9xDP6f8rsusUnI/5XFT+614BaRjMFhBe6hhO90txHqQeKY',
);

/// OpenSSL-computed SPKI pin for [kRogueCertDer].
const String kRoguePin = 'sha256/K6Cl1771WCRhwR1l9W59+cxHYygDG7C8Ffbc37JXa2w=';

/// A well-formed pin string that matches neither fixture certificate.
const String kUnrelatedPin =
    'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
