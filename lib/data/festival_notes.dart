/// What to show on a festival or national day. Solemn days have no greeting.
class FestivalNote {
  const FestivalNote(this.about, {this.greeting, this.english});

  final String about;
  final String? greeting;
  final String? english;
}

/// Keyed by [Observance.name].
const festivalNotes = {
  'Nepali New Year': FestivalNote(
    'The first day of Baishakh opens the Bikram Sambat year.',
    greeting: 'नयाँ वर्षको हार्दिक मंगलमय शुभकामना',
    english: 'Happy New Year',
  ),
  'Republic Day': FestivalNote(
    'Marks the day in 2008 when Nepal became a federal republic.',
    greeting: 'गणतन्त्र दिवसको हार्दिक शुभकामना',
    english: 'Happy Republic Day',
  ),
  'Saune Sankranti': FestivalNote(
    'The first of Saun, the start of the sun\'s southward journey.',
    greeting: 'साउने संक्रान्तिको शुभकामना',
    english: 'Happy Saune Sankranti',
  ),
  'Constitution Day': FestivalNote(
    'Marks the promulgation of the Constitution of Nepal in 2015.',
    greeting: 'संविधान दिवसको हार्दिक शुभकामना',
    english: 'Happy Constitution Day',
  ),
  'Prithvi Jayanti': FestivalNote(
    'The birth anniversary of Prithvi Narayan Shah, who unified modern Nepal.',
    greeting: 'पृथ्वी जयन्तीको शुभकामना',
    english: 'Happy Prithvi Jayanti',
  ),
  'Maghe Sankranti': FestivalNote(
    'The sun turns north. Families share ghee, chaku, tilko laddu and yam.',
    greeting: 'माघे संक्रान्तिको हार्दिक शुभकामना',
    english: 'Happy Maghe Sankranti',
  ),
  'Martyrs\' Day': FestivalNote(
    'Remembers those who gave their lives for Nepal, including the four '
    'martyrs of 1941.',
  ),
  'Democracy Day': FestivalNote(
    'Marks the end of Rana rule in 1951.',
    greeting: 'प्रजातन्त्र दिवसको हार्दिक शुभकामना',
    english: 'Happy Democracy Day',
  ),
  'International Women\'s Day': FestivalNote(
    'A day to celebrate women and to press for equality.',
    greeting: 'अन्तर्राष्ट्रिय महिला दिवसको शुभकामना',
    english: 'Happy International Women\'s Day',
  ),
  'Labour Day': FestivalNote(
    'Honours workers around the world.',
    greeting: 'श्रमिक दिवसको शुभकामना',
    english: 'Happy Labour Day',
  ),
  'Christmas': FestivalNote(
    'Celebrates the birth of Jesus Christ.',
    greeting: 'क्रिसमसको शुभकामना',
    english: 'Merry Christmas',
  ),
  'Buddha Jayanti': FestivalNote(
    'The birth, enlightenment and passing of the Buddha, who was born in '
    'Lumbini.',
    greeting: 'बुद्ध जयन्तीको हार्दिक शुभकामना',
    english: 'Happy Buddha Jayanti',
  ),
  'Janai Purnima': FestivalNote(
    'Sacred threads are changed and rakhi is tied. Kwati, a soup of nine '
    'beans, is shared.',
    greeting: 'जनै पूर्णिमाको हार्दिक शुभकामना',
    english: 'Happy Janai Purnima',
  ),
  'Gai Jatra': FestivalNote(
    'Families who lost someone this year parade with cows, and satire and '
    'humour fill the streets.',
  ),
  'Krishna Janmashtami': FestivalNote(
    'The birth of Lord Krishna, kept with fasting and midnight prayers.',
    greeting: 'श्रीकृष्ण जन्माष्टमीको हार्दिक शुभकामना',
    english: 'Happy Krishna Janmashtami',
  ),
  'Haritalika Teej': FestivalNote(
    'Women fast, sing and dance in red, praying to Parvati and Shiva.',
    greeting: 'हरितालिका तीजको हार्दिक शुभकामना',
    english: 'Happy Teej',
  ),
  'Ghatasthapana': FestivalNote(
    'The first day of Dashain. Barley is sown for jamara and the kalash is '
    'set up.',
    greeting: 'बडा दशैंको शुभारम्भको शुभकामना',
    english: 'Happy Ghatasthapana',
  ),
  'Fulpati': FestivalNote(
    'The seventh day of Dashain, when sacred flowers and leaves are brought '
    'to the home.',
    greeting: 'फूलपातीको शुभकामना',
    english: 'Happy Fulpati',
  ),
  'Maha Ashtami': FestivalNote(
    'The eighth day of Dashain, devoted to the fierce goddess Kali.',
    greeting: 'महाअष्टमीको शुभकामना',
    english: 'Happy Maha Ashtami',
  ),
  'Maha Navami': FestivalNote(
    'The ninth day of Dashain, when vehicles and tools are worshipped.',
    greeting: 'महानवमीको शुभकामना',
    english: 'Happy Maha Navami',
  ),
  'Vijaya Dashami': FestivalNote(
    'Elders place tika and jamara on younger relatives and give blessings.',
    greeting: 'विजया दशमीको हार्दिक मंगलमय शुभकामना',
    english: 'Happy Vijaya Dashami',
  ),
  'Kojagrat Purnima': FestivalNote(
    'The full moon that closes Dashain, when Laxmi is said to ask who is '
    'awake.',
    greeting: 'कोजाग्रत पूर्णिमाको शुभकामना',
    english: 'Happy Kojagrat Purnima',
  ),
  'Laxmi Puja': FestivalNote(
    'Homes glow with lamps to welcome Laxmi, and children sing deusi-bhailo.',
    greeting: 'शुभ दीपावलीको हार्दिक मंगलमय शुभकामना',
    english: 'Happy Deepawali',
  ),
  'Govardhan Puja': FestivalNote(
    'Oxen and Govardhan hill are worshipped during Tihar. Newars celebrate '
    'Mha Puja and Nepal Sambat New Year around this time.',
    greeting: 'गोवर्धन पूजाको शुभकामना',
    english: 'Happy Govardhan Puja',
  ),
  'Bhai Tika': FestivalNote(
    'Sisters place seven-coloured tika on their brothers and pray for their '
    'long life.',
    greeting: 'भाइटीकाको हार्दिक शुभकामना',
    english: 'Happy Bhai Tika',
  ),
  'Chhath': FestivalNote(
    'Devotees offer prayers to the setting and rising sun at rivers and ponds.',
    greeting: 'छठ पर्वको हार्दिक शुभकामना',
    english: 'Happy Chhath',
  ),
  'Maha Shivaratri': FestivalNote(
    'The great night of Shiva, when devotees gather at Pashupatinath.',
    greeting: 'महाशिवरात्रिको हार्दिक शुभकामना',
    english: 'Happy Maha Shivaratri',
  ),
  'Fagu Purnima': FestivalNote(
    'Holi, the festival of colours.',
    greeting: 'फागु पूर्णिमाको हार्दिक शुभकामना',
    english: 'Happy Holi',
  ),
  'Ram Navami': FestivalNote(
    'The birth of Lord Ram, celebrated especially in Janakpur.',
    greeting: 'राम नवमीको हार्दिक शुभकामना',
    english: 'Happy Ram Navami',
  ),
};
