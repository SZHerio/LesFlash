# Фоны района «Приречье»

Шесть базовых фонов M2 созданы встроенным генератором изображений с нуля, без входных референсов. Для каждой локации хранится ровно одно исходное изображение; депрессивность, потеря насыщенности и виньетка накладываются в Godot шейдером, поэтому визуальные дубликаты под разные состояния психики не нужны.

## Общая часть prompt set

> Portrait 9:16 high-quality hand-painted stylized-realistic environment for a mobile text survival RPG. A fictional Eastern-European city around the 1970s, believable worn architecture and period details, bright clear daytime and natural colors suitable for later mood grading. Environment only, no protagonist close-up, no UI, no captions, no letters, no logos, no watermark. Leave calm readable areas for translucent game panels.

К общей части поочерёдно добавлялись следующие сцены:

1. `riverside_underpass_day` — старый железнодорожный подземный переход, кафель, ржавый мост, лестницы, лавка и картон, солнечный выход.
2. `riverside_market_day` — открытый продуктовый рынок, деревянные ящики, навесы, овощи и старая кирпичная рыночная постройка.
3. `riverside_station_square_day` — площадь перед каменным вокзалом, старые автобусы, трамвайные или троллейбусные провода, скамьи.
4. `riverside_recycling_point_day` — двор пункта приёма вторсырья с зонами бумаги, стекла и металлолома.
5. `riverside_clinic_yard_day` — двор небольшой поликлиники, светлый фасад, деревья, лавка и велосипеды.
6. `riverside_embankment_day` — каменная речная набережная, прогулочная дорожка, лодка, мост и город на другом берегу.

Режим генерации: `imagegen`, новый растр; `referenced_image_paths` и `num_last_images_to_include` не использовались. Исходный размер каждого PNG — 941 × 1672.
