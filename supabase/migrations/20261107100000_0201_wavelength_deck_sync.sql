-- Wavelength deck sync with docs/games/wavelength/cards.md: drop the cards rejected
-- since 0161 seeded the deck, relabel the two reworded ones, and add the new
-- approved cards (129-151). `card_id` stays the number in the review file.
--
-- wavelength_cards copies the labels it was dealt, so a finished match never needs
-- the deck row again. Drop the foreign key so retiring a card does not collide
-- with the matches that already used it.
alter table public.wavelength_cards drop constraint if exists wavelength_cards_card_id_fkey;

delete from wavelength_private.deck where card_id in (10, 12, 14, 15, 21, 22, 24, 29, 30, 32, 35, 37, 40, 41, 65, 67, 69, 71, 74, 77, 78, 79, 80, 81, 82, 84, 85, 86, 87, 88, 89, 93, 94, 95, 96, 98, 99, 100, 101, 103, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 121, 122, 123, 124, 126, 127);

update wavelength_private.deck set left_label = 'Bad defense', right_label = 'Good defense' where card_id = 31;
update wavelength_private.deck set left_label = 'Backup QB who stinks', right_label = 'Backup QB you''d trust' where card_id = 83;

insert into wavelength_private.deck (card_id, left_label, right_label) values
  (129, 'Overrated QB', 'Underrated QB'),
  (130, 'Overrated RB', 'Underrated RB'),
  (131, 'Overrated WR', 'Underrated WR'),
  (132, 'Overrated backup QB', 'Underrated backup QB'),
  (133, 'Overrated RB2', 'Underrated RB2'),
  (134, 'Overrated WR2', 'Underrated WR2'),
  (135, 'Overrated TE', 'Underrated TE'),
  (136, 'Overrated defensive player', 'Underrated defensive player'),
  (137, 'Overrated coach', 'Underrated coach'),
  (138, 'Overrated team', 'Underrated team'),
  (139, 'Bad QB', 'Good QB'),
  (140, 'Bad backup QB', 'Good backup QB'),
  (141, 'Bad RB1', 'Good RB1'),
  (142, 'Bad RB2', 'Good RB2'),
  (143, 'Bad WR1', 'Good WR1'),
  (144, 'Bad WR2', 'Good WR2'),
  (145, 'Bad TE', 'Good TE'),
  (146, 'Bad defensive player', 'Good defensive player'),
  (147, 'Bad coach', 'Good coach'),
  (148, 'Bad team', 'Good team'),
  (149, 'Slow QB', 'Fast QB'),
  (150, 'Slow RB', 'Fast RB'),
  (151, 'Slow WR', 'Fast WR');
