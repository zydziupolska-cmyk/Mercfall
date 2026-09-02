/// System żywności — armia musi jeść, dieta wpływa na morale.

enum FoodType { bread, rations, feast }

extension FoodTypeInfo on FoodType {
  String get plName => switch (this) {
    FoodType.bread   => 'Chleb',
    FoodType.rations => 'Prowiant',
    FoodType.feast   => 'Uczta',
  };

  String get emoji => switch (this) {
    FoodType.bread   => '🍞',
    FoodType.rations => '🥩',
    FoodType.feast   => '🍖',
  };

  String get plDesc => switch (this) {
    FoodType.bread   => 'Podstawowy — neutralne morale',
    FoodType.rations => 'Wojskowy — +8 morale/dzień',
    FoodType.feast   => 'Uczta — +22 morale/dzień',
  };

  /// Koszt 1 jednostki (żywi 10 żołnierzy przez 1 dzień).
  int get costPerUnit => switch (this) {
    FoodType.bread   => 2,
    FoodType.rations => 5,
    FoodType.feast   => 15,
  };

  /// Zmiana morale kampanijnego za dzień dobrego jedzenia.
  double get moralePerDay => switch (this) {
    FoodType.bread   =>  0.0,
    FoodType.rations =>  8.0,
    FoodType.feast   => 22.0,
  };

  /// Gdzie można kupić ten rodzaj jedzenia.
  bool get soldInCity    => true;
  bool get soldInVillage => this != FoodType.feast;
}

/// Kara moralna gdy armia nie ma nic do jedzenia.
const double kStarvationMoralePenalty = -20.0;

/// Ile jednostek jedzenia potrzeba na 1 dzień dla [soldiers] żołnierzy.
int dailyFoodUnits(int soldiers) => ((soldiers / 10).ceil()).clamp(1, 999);