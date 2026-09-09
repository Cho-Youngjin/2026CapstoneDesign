package com.travelfootsteps.country;

public record CountryResponse(
        String isoAlpha2,
        String nameKo,
        String nameEn,
        String continent,
        String tier
) {
    public static CountryResponse from(Country country) {
        return new CountryResponse(
                country.getIsoAlpha2(),
                country.getNameKo(),
                country.getNameEn(),
                country.getContinent(),
                country.getTier()
        );
    }
}
