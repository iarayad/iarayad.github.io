"""Update publication metadata while preserving the YAML guidance header."""

import subprocess

from normalize_publications import PUBLICATIONS, guidance_header, normalize


def main() -> None:
    header = guidance_header(PUBLICATIONS)
    subprocess.run(
        [
            "publist",
            str(PUBLICATIONS),
            "--author_id",
            "arayaday_i_1",
            "--update",
            "--silent",
            "--email",
            "iarayaday@gmail.com",
        ],
        check=True,
    )
    normalize(PUBLICATIONS, header=header)


if __name__ == "__main__":
    main()
