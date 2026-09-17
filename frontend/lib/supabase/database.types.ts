export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  auction: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      expire_turn: {
        Args: { p_match_id: string }
        Returns: Database["auction"]["CompositeTypes"]["turn"]
        SetofOptions: {
          from: "*"
          to: "turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      pass_lot: {
        Args: { p_match_id: string }
        Returns: Database["auction"]["CompositeTypes"]["turn"]
        SetofOptions: {
          from: "*"
          to: "turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      place_bid: {
        Args: { p_amount: number; p_match_id: string }
        Returns: Database["auction"]["CompositeTypes"]["turn"]
        SetofOptions: {
          from: "*"
          to: "turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      season_bounds: {
        Args: never
        Returns: Database["auction"]["CompositeTypes"]["era"]
        SetofOptions: {
          from: "*"
          to: "era"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      start: {
        Args: {
          p_match_id: string
          p_roster_preset: string
          p_scoring_mode: string
          p_season_from?: number
          p_season_to?: number
        }
        Returns: Database["auction"]["CompositeTypes"]["turn"]
        SetofOptions: {
          from: "*"
          to: "turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      state: {
        Args: { p_match_id: string }
        Returns: Database["auction"]["CompositeTypes"]["turn"]
        SetofOptions: {
          from: "*"
          to: "turn"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      era: {
        season_min: number | null
        season_max: number | null
        min_span: number | null
      }
      turn: {
        match_id: string | null
        lot_count: number | null
        current_lot: number | null
        turn_seat: number | null
        opener_seat: number | null
        turn_deadline: string | null
        server_now: string | null
        phase: string | null
        phase_deadline: string | null
        free_fallback_seat: number | null
      }
    }
  }
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  higher_or_lower: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      advance: {
        Args: { p_match_id: string }
        Returns: Database["higher_or_lower"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      call: {
        Args: { p_direction: string; p_match_id: string }
        Returns: Database["public"]["Tables"]["higher_or_lower_calls"]["Row"]
        SetofOptions: {
          from: "*"
          to: "higher_or_lower_calls"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      season_bounds: {
        Args: never
        Returns: Database["higher_or_lower"]["CompositeTypes"]["era"]
        SetofOptions: {
          from: "*"
          to: "era"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      start: {
        Args: {
          p_match_id: string
          p_scoring_mode?: string
          p_season_from?: number
          p_season_to?: number
        }
        Returns: Database["higher_or_lower"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      state: {
        Args: { p_match_id: string }
        Returns: Database["higher_or_lower"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      tick: {
        Args: { p_match_id: string }
        Returns: Database["higher_or_lower"]["CompositeTypes"]["board"]
        SetofOptions: {
          from: "*"
          to: "board"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      board: {
        match_id: string | null
        question_count: number | null
        spare_count: number | null
        current_question: number | null
        scoring_mode: string | null
        season_from: number | null
        season_to: number | null
        phase: string | null
        phase_deadline: string | null
        server_now: string | null
      }
      era: {
        season_min: number | null
        season_max: number | null
      }
    }
  }
  prompts: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      create_post: {
        Args: {
          p_caption: string
          p_is_opinion?: boolean
          p_lock_at: string
          p_prompt_text: string
          p_resolution_criteria: string
          p_resolution_source?: Json
          p_slots: Json
          p_template_kind: string
          p_template_name: string
        }
        Returns: string
      }
      player_options: {
        Args: never
        Returns: {
          display_name: string
          headshot_url: string
          player_id: string
          position: string
          team: string
        }[]
      }
      post_aggregates: {
        Args: { p_post_id: string }
        Returns: {
          option_id: string
          pct: number
          slot_id: string
          total_responses: number
        }[]
      }
      post_comment: {
        Args: {
          p_body: string
          p_parent_comment_id?: string
          p_post_id: string
        }
        Returns: string
      }
      resolve_post: {
        Args: { p_answers: Json; p_post_id: string }
        Returns: undefined
      }
      revealed_responses: {
        Args: { p_post_id: string }
        Returns: {
          chosen_option_ids: string[]
          profile_id: string
          slot_id: string
        }[]
      }
      submit_response: {
        Args: { p_choices: Json; p_comment?: string; p_post_id: string }
        Returns: undefined
      }
      void_post: {
        Args: { p_post_id: string; p_reason: string }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      auction_bids: {
        Row: {
          action: string
          automatic: boolean
          bid_seq: number
          by_timeout: boolean
          created_at: string
          match_id: string
          price: number | null
          seq: number
          user_id: string
        }
        Insert: {
          action: string
          automatic?: boolean
          bid_seq: number
          by_timeout?: boolean
          created_at?: string
          match_id: string
          price?: number | null
          seq: number
          user_id: string
        }
        Update: {
          action?: string
          automatic?: boolean
          bid_seq?: number
          by_timeout?: boolean
          created_at?: string
          match_id?: string
          price?: number | null
          seq?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "auction_bids_match_id_seq_fkey"
            columns: ["match_id", "seq"]
            isOneToOne: false
            referencedRelation: "auction_lots"
            referencedColumns: ["match_id", "seq"]
          },
          {
            foreignKeyName: "auction_bids_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      auction_lots: {
        Row: {
          display_name: string
          headshot_url: string | null
          match_id: string
          opponent: string | null
          player_id: string
          points: number | null
          position: string
          price: number | null
          resolved_at: string | null
          season: number
          seq: number
          slot: string | null
          team: string
          week: number | null
          winner_id: string | null
        }
        Insert: {
          display_name: string
          headshot_url?: string | null
          match_id: string
          opponent?: string | null
          player_id: string
          points?: number | null
          position: string
          price?: number | null
          resolved_at?: string | null
          season: number
          seq: number
          slot?: string | null
          team: string
          week?: number | null
          winner_id?: string | null
        }
        Update: {
          display_name?: string
          headshot_url?: string | null
          match_id?: string
          opponent?: string | null
          player_id?: string
          points?: number | null
          position?: string
          price?: number | null
          resolved_at?: string | null
          season?: number
          seq?: number
          slot?: string | null
          team?: string
          week?: number | null
          winner_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "auction_lots_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "auction_lots_winner_id_fkey"
            columns: ["winner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      auction_matches: {
        Row: {
          current_lot: number
          flex_slots: number | null
          free_fallback_seat: number | null
          lot_count: number
          match_id: string
          opener_seat: number
          phase: string
          phase_deadline: string | null
          purse: number | null
          qb_slots: number | null
          rb_slots: number | null
          roster_preset: string | null
          scoring_mode: string | null
          season_from: number | null
          season_to: number | null
          te_slots: number | null
          turn_deadline: string | null
          turn_seat: number | null
          wr_slots: number | null
        }
        Insert: {
          current_lot?: number
          flex_slots?: number | null
          free_fallback_seat?: number | null
          lot_count: number
          match_id: string
          opener_seat?: number
          phase?: string
          phase_deadline?: string | null
          purse?: number | null
          qb_slots?: number | null
          rb_slots?: number | null
          roster_preset?: string | null
          scoring_mode?: string | null
          season_from?: number | null
          season_to?: number | null
          te_slots?: number | null
          turn_deadline?: string | null
          turn_seat?: number | null
          wr_slots?: number | null
        }
        Update: {
          current_lot?: number
          flex_slots?: number | null
          free_fallback_seat?: number | null
          lot_count?: number
          match_id?: string
          opener_seat?: number
          phase?: string
          phase_deadline?: string | null
          purse?: number | null
          qb_slots?: number | null
          rb_slots?: number | null
          roster_preset?: string | null
          scoring_mode?: string | null
          season_from?: number | null
          season_to?: number | null
          te_slots?: number | null
          turn_deadline?: string | null
          turn_seat?: number | null
          wr_slots?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "auction_matches_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: true
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      auction_players: {
        Row: {
          budget: number
          match_id: string
          seat: number
          user_id: string
        }
        Insert: {
          budget?: number
          match_id: string
          seat: number
          user_id: string
        }
        Update: {
          budget?: number
          match_id?: string
          seat?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "auction_players_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "auction_players_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      feedback: {
        Row: {
          created_at: string
          id: string
          kind: string
          message: string
          reporter_id: string | null
          route: string
          status: string
        }
        Insert: {
          created_at?: string
          id?: string
          kind: string
          message: string
          reporter_id?: string | null
          route: string
          status?: string
        }
        Update: {
          created_at?: string
          id?: string
          kind?: string
          message?: string
          reporter_id?: string | null
          route?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "feedback_reporter_id_fkey"
            columns: ["reporter_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      guest_account_collisions: {
        Row: {
          account_id: string | null
          claim_nonce: string | null
          claimed_at: string | null
          created_at: string
          guest_id: string
        }
        Insert: {
          account_id?: string | null
          claim_nonce?: string | null
          claimed_at?: string | null
          created_at?: string
          guest_id: string
        }
        Update: {
          account_id?: string | null
          claim_nonce?: string | null
          claimed_at?: string | null
          created_at?: string
          guest_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "guest_account_collisions_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "guest_account_collisions_guest_id_fkey"
            columns: ["guest_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      higher_or_lower_call_statuses: {
        Row: {
          match_id: string
          question: number
          user_id: string
        }
        Insert: {
          match_id: string
          question: number
          user_id: string
        }
        Update: {
          match_id?: string
          question?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "higher_or_lower_call_statuses_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "higher_or_lower_call_statuses_match_id_user_id_fkey"
            columns: ["match_id", "user_id"]
            isOneToOne: false
            referencedRelation: "higher_or_lower_players"
            referencedColumns: ["match_id", "user_id"]
          },
          {
            foreignKeyName: "higher_or_lower_call_statuses_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      higher_or_lower_calls: {
        Row: {
          created_at: string
          direction: string | null
          match_id: string
          question: number
          timed_out: boolean
          user_id: string
        }
        Insert: {
          created_at?: string
          direction?: string | null
          match_id: string
          question: number
          timed_out?: boolean
          user_id: string
        }
        Update: {
          created_at?: string
          direction?: string | null
          match_id?: string
          question?: number
          timed_out?: boolean
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "higher_or_lower_calls_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "higher_or_lower_calls_match_id_user_id_fkey"
            columns: ["match_id", "user_id"]
            isOneToOne: false
            referencedRelation: "higher_or_lower_players"
            referencedColumns: ["match_id", "user_id"]
          },
          {
            foreignKeyName: "higher_or_lower_calls_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      higher_or_lower_cards: {
        Row: {
          display_name: string
          headshot_url: string | null
          match_id: string
          opponent: string | null
          ordinal: number
          player_id: string
          points: number | null
          position: string
          revealed_at: string | null
          season: number
          team: string
          week: number | null
        }
        Insert: {
          display_name: string
          headshot_url?: string | null
          match_id: string
          opponent?: string | null
          ordinal: number
          player_id: string
          points?: number | null
          position: string
          revealed_at?: string | null
          season: number
          team: string
          week?: number | null
        }
        Update: {
          display_name?: string
          headshot_url?: string | null
          match_id?: string
          opponent?: string | null
          ordinal?: number
          player_id?: string
          points?: number | null
          position?: string
          revealed_at?: string | null
          season?: number
          team?: string
          week?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "higher_or_lower_cards_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      higher_or_lower_matches: {
        Row: {
          current_question: number
          is_solo: boolean
          match_id: string
          phase: string
          phase_deadline: string | null
          question_count: number
          question_started_at: string | null
          scoring_mode: string
          season_from: number
          season_to: number
          spare_count: number
        }
        Insert: {
          current_question?: number
          is_solo?: boolean
          match_id: string
          phase?: string
          phase_deadline?: string | null
          question_count: number
          question_started_at?: string | null
          scoring_mode: string
          season_from: number
          season_to: number
          spare_count: number
        }
        Update: {
          current_question?: number
          is_solo?: boolean
          match_id?: string
          phase?: string
          phase_deadline?: string | null
          question_count?: number
          question_started_at?: string | null
          scoring_mode?: string
          season_from?: number
          season_to?: number
          spare_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "higher_or_lower_matches_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: true
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      higher_or_lower_players: {
        Row: {
          absent: boolean
          best_streak: number
          correct_count: number
          current_streak: number
          eliminated_at: number | null
          last_seen_at: string
          match_id: string
          seat: number
          sudden_death: boolean
          user_id: string
        }
        Insert: {
          absent?: boolean
          best_streak?: number
          correct_count?: number
          current_streak?: number
          eliminated_at?: number | null
          last_seen_at?: string
          match_id: string
          seat: number
          sudden_death?: boolean
          user_id: string
        }
        Update: {
          absent?: boolean
          best_streak?: number
          correct_count?: number
          current_streak?: number
          eliminated_at?: number | null
          last_seen_at?: string
          match_id?: string
          seat?: number
          sudden_death?: boolean
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "higher_or_lower_players_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "higher_or_lower_players_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      lobbies: {
        Row: {
          closed_at: string | null
          code: string
          created_at: string
          host_id: string
          id: string
          selected_game: string | null
        }
        Insert: {
          closed_at?: string | null
          code: string
          created_at?: string
          host_id: string
          id?: string
          selected_game?: string | null
        }
        Update: {
          closed_at?: string | null
          code?: string
          created_at?: string
          host_id?: string
          id?: string
          selected_game?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lobbies_host_id_fkey"
            columns: ["host_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      lobby_members: {
        Row: {
          joined_at: string
          last_seen_at: string
          left_at: string | null
          lobby_id: string
          user_id: string
        }
        Insert: {
          joined_at?: string
          last_seen_at?: string
          left_at?: string | null
          lobby_id: string
          user_id: string
        }
        Update: {
          joined_at?: string
          last_seen_at?: string
          left_at?: string | null
          lobby_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "lobby_members_lobby_id_fkey"
            columns: ["lobby_id"]
            isOneToOne: false
            referencedRelation: "lobbies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lobby_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      match_players: {
        Row: {
          match_id: string
          placement: number | null
          points_awarded: number | null
          raw_score: number | null
          run_id: string
          team: number | null
          user_id: string
        }
        Insert: {
          match_id: string
          placement?: number | null
          points_awarded?: number | null
          raw_score?: number | null
          run_id: string
          team?: number | null
          user_id: string
        }
        Update: {
          match_id?: string
          placement?: number | null
          points_awarded?: number | null
          raw_score?: number | null
          run_id?: string
          team?: number | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "match_players_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_players_run_id_user_id_fkey"
            columns: ["run_id", "user_id"]
            isOneToOne: false
            referencedRelation: "run_participants"
            referencedColumns: ["run_id", "user_id"]
          },
        ]
      }
      matches: {
        Row: {
          ended_at: string | null
          game: string
          id: string
          paused_at: string | null
          run_id: string
          seq: number
          started_at: string | null
          status: Database["public"]["Enums"]["match_status"]
        }
        Insert: {
          ended_at?: string | null
          game: string
          id?: string
          paused_at?: string | null
          run_id: string
          seq: number
          started_at?: string | null
          status?: Database["public"]["Enums"]["match_status"]
        }
        Update: {
          ended_at?: string | null
          game?: string
          id?: string
          paused_at?: string | null
          run_id?: string
          seq?: number
          started_at?: string | null
          status?: Database["public"]["Enums"]["match_status"]
        }
        Relationships: [
          {
            foreignKeyName: "matches_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
        ]
      }
      post_game_actions: {
        Row: {
          choice: Database["public"]["Enums"]["post_game_choice"]
          chosen_at: string
          match_id: string
          next_match_id: string | null
        }
        Insert: {
          choice: Database["public"]["Enums"]["post_game_choice"]
          chosen_at?: string
          match_id: string
          next_match_id?: string | null
        }
        Update: {
          choice?: Database["public"]["Enums"]["post_game_choice"]
          chosen_at?: string
          match_id?: string
          next_match_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "post_game_actions_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: true
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "post_game_actions_next_match_id_fkey"
            columns: ["next_match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          deleted_at: string | null
          display_name: string
          id: string
          is_guest: boolean
          rankings_visible: boolean
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          deleted_at?: string | null
          display_name: string
          id: string
          is_guest?: boolean
          rankings_visible?: boolean
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          deleted_at?: string | null
          display_name?: string
          id?: string
          is_guest?: boolean
          rankings_visible?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      prompt_comments: {
        Row: {
          author_id: string
          body: string
          created_at: string
          id: string
          parent_comment_id: string | null
          post_id: string
          posted_with_pick: boolean
        }
        Insert: {
          author_id: string
          body: string
          created_at?: string
          id?: string
          parent_comment_id?: string | null
          post_id: string
          posted_with_pick?: boolean
        }
        Update: {
          author_id?: string
          body?: string
          created_at?: string
          id?: string
          parent_comment_id?: string | null
          post_id?: string
          posted_with_pick?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "prompt_comments_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prompt_comments_parent_comment_id_fkey"
            columns: ["parent_comment_id"]
            isOneToOne: false
            referencedRelation: "prompt_comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prompt_comments_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "prompt_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      prompt_posts: {
        Row: {
          author_id: string
          caption: string
          created_at: string
          id: string
          is_opinion: boolean
          lock_at: string
          prompt_text: string
          resolution_criteria: string
          resolution_source: Json | null
          resolved_at: string | null
          status: string
          template_kind: string
          template_name: string
          void_reason: string | null
        }
        Insert: {
          author_id: string
          caption: string
          created_at?: string
          id?: string
          is_opinion?: boolean
          lock_at: string
          prompt_text: string
          resolution_criteria: string
          resolution_source?: Json | null
          resolved_at?: string | null
          status?: string
          template_kind: string
          template_name: string
          void_reason?: string | null
        }
        Update: {
          author_id?: string
          caption?: string
          created_at?: string
          id?: string
          is_opinion?: boolean
          lock_at?: string
          prompt_text?: string
          resolution_criteria?: string
          resolution_source?: Json | null
          resolved_at?: string | null
          status?: string
          template_kind?: string
          template_name?: string
          void_reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "prompt_posts_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      prompt_responses: {
        Row: {
          chosen_option_ids: string[]
          created_at: string
          id: string
          points_earned: number | null
          post_id: string
          profile_id: string
          slot_id: string
        }
        Insert: {
          chosen_option_ids: string[]
          created_at?: string
          id?: string
          points_earned?: number | null
          post_id: string
          profile_id: string
          slot_id: string
        }
        Update: {
          chosen_option_ids?: string[]
          created_at?: string
          id?: string
          points_earned?: number | null
          post_id?: string
          profile_id?: string
          slot_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "prompt_responses_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "prompt_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prompt_responses_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prompt_responses_slot_id_fkey"
            columns: ["slot_id"]
            isOneToOne: false
            referencedRelation: "prompt_slots"
            referencedColumns: ["id"]
          },
        ]
      }
      prompt_slot_exclusions: {
        Row: {
          excluded_slot_id: string
          slot_id: string
        }
        Insert: {
          excluded_slot_id: string
          slot_id: string
        }
        Update: {
          excluded_slot_id?: string
          slot_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "prompt_slot_exclusions_excluded_slot_id_fkey"
            columns: ["excluded_slot_id"]
            isOneToOne: false
            referencedRelation: "prompt_slots"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prompt_slot_exclusions_slot_id_fkey"
            columns: ["slot_id"]
            isOneToOne: false
            referencedRelation: "prompt_slots"
            referencedColumns: ["id"]
          },
        ]
      }
      prompt_slot_options: {
        Row: {
          headshot_url: string | null
          id: string
          label: string
          slot_id: string
          sort_order: number
          sublabel: string | null
          team_code: string | null
        }
        Insert: {
          headshot_url?: string | null
          id?: string
          label: string
          slot_id: string
          sort_order?: number
          sublabel?: string | null
          team_code?: string | null
        }
        Update: {
          headshot_url?: string | null
          id?: string
          label?: string
          slot_id?: string
          sort_order?: number
          sublabel?: string | null
          team_code?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "prompt_slot_options_slot_id_fkey"
            columns: ["slot_id"]
            isOneToOne: false
            referencedRelation: "prompt_slots"
            referencedColumns: ["id"]
          },
        ]
      }
      prompt_slots: {
        Row: {
          correct_option_ids: string[] | null
          id: string
          label: string
          pick_count: number | null
          points: number
          post_id: string
          shape: string
          sort_order: number
          source_game_id: string | null
        }
        Insert: {
          correct_option_ids?: string[] | null
          id?: string
          label: string
          pick_count?: number | null
          points: number
          post_id: string
          shape: string
          sort_order?: number
          source_game_id?: string | null
        }
        Update: {
          correct_option_ids?: string[] | null
          id?: string
          label?: string
          pick_count?: number | null
          points?: number
          post_id?: string
          shape?: string
          sort_order?: number
          source_game_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "prompt_slots_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "prompt_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      run_participants: {
        Row: {
          run_id: string
          score: number
          seat: number
          user_id: string
        }
        Insert: {
          run_id: string
          score?: number
          seat: number
          user_id: string
        }
        Update: {
          run_id?: string
          score?: number
          seat?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "run_participants_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "run_participants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      runs: {
        Row: {
          ended_at: string | null
          id: string
          lobby_id: string | null
          mode: Database["public"]["Enums"]["run_mode"]
          started_at: string
          status: Database["public"]["Enums"]["run_status"]
          target_score: number | null
        }
        Insert: {
          ended_at?: string | null
          id?: string
          lobby_id?: string | null
          mode: Database["public"]["Enums"]["run_mode"]
          started_at?: string
          status?: Database["public"]["Enums"]["run_status"]
          target_score?: number | null
        }
        Update: {
          ended_at?: string | null
          id?: string
          lobby_id?: string | null
          mode?: Database["public"]["Enums"]["run_mode"]
          started_at?: string
          status?: Database["public"]["Enums"]["run_status"]
          target_score?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "runs_lobby_id_fkey"
            columns: ["lobby_id"]
            isOneToOne: false
            referencedRelation: "lobbies"
            referencedColumns: ["id"]
          },
        ]
      }
      sabotage_draft_guesses: {
        Row: {
          created_at: string
          id: number
          match_id: string
          player_id: string
          replacement_player_id: string | null
          replacement_season: number | null
          result: Database["sabotage_draft"]["Enums"]["guess_result"] | null
          round_number: number
          season: number | null
          target_user_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: never
          match_id: string
          player_id: string
          replacement_player_id?: string | null
          replacement_season?: number | null
          result?: Database["sabotage_draft"]["Enums"]["guess_result"] | null
          round_number: number
          season?: number | null
          target_user_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: never
          match_id?: string
          player_id?: string
          replacement_player_id?: string | null
          replacement_season?: number | null
          result?: Database["sabotage_draft"]["Enums"]["guess_result"] | null
          round_number?: number
          season?: number | null
          target_user_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sabotage_draft_guesses_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sabotage_draft_guesses_match_id_target_user_id_fkey"
            columns: ["match_id", "target_user_id"]
            isOneToOne: false
            referencedRelation: "sabotage_draft_players"
            referencedColumns: ["match_id", "user_id"]
          },
          {
            foreignKeyName: "sabotage_draft_guesses_match_id_user_id_fkey"
            columns: ["match_id", "user_id"]
            isOneToOne: false
            referencedRelation: "sabotage_draft_players"
            referencedColumns: ["match_id", "user_id"]
          },
        ]
      }
      sabotage_draft_matches: {
        Row: {
          active_seat: number
          current_round: number
          match_id: string
          round_count: number
          turn_deadline: string | null
          x_factor_open: boolean
        }
        Insert: {
          active_seat?: number
          current_round?: number
          match_id: string
          round_count?: number
          turn_deadline?: string | null
          x_factor_open?: boolean
        }
        Update: {
          active_seat?: number
          current_round?: number
          match_id?: string
          round_count?: number
          turn_deadline?: string | null
          x_factor_open?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "sabotage_draft_matches_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: true
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      sabotage_draft_passes: {
        Row: {
          created_at: string
          match_id: string
          round_number: number
          target_user_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          match_id: string
          round_number: number
          target_user_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          match_id?: string
          round_number?: number
          target_user_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sabotage_draft_passes_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sabotage_draft_passes_match_id_target_user_id_fkey"
            columns: ["match_id", "target_user_id"]
            isOneToOne: false
            referencedRelation: "sabotage_draft_players"
            referencedColumns: ["match_id", "user_id"]
          },
          {
            foreignKeyName: "sabotage_draft_passes_match_id_user_id_fkey"
            columns: ["match_id", "user_id"]
            isOneToOne: false
            referencedRelation: "sabotage_draft_players"
            referencedColumns: ["match_id", "user_id"]
          },
        ]
      }
      sabotage_draft_pick_hits: {
        Row: {
          created_at: string
          guesser_user_id: string
          kind: string
          match_id: string
          round_number: number
          target_user_id: string
        }
        Insert: {
          created_at?: string
          guesser_user_id: string
          kind: string
          match_id: string
          round_number: number
          target_user_id: string
        }
        Update: {
          created_at?: string
          guesser_user_id?: string
          kind?: string
          match_id?: string
          round_number?: number
          target_user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sabotage_draft_pick_hits_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sabotage_draft_pick_hits_match_id_guesser_user_id_fkey"
            columns: ["match_id", "guesser_user_id"]
            isOneToOne: false
            referencedRelation: "sabotage_draft_players"
            referencedColumns: ["match_id", "user_id"]
          },
          {
            foreignKeyName: "sabotage_draft_pick_hits_match_id_target_user_id_fkey"
            columns: ["match_id", "target_user_id"]
            isOneToOne: false
            referencedRelation: "sabotage_draft_players"
            referencedColumns: ["match_id", "user_id"]
          },
        ]
      }
      sabotage_draft_pick_statuses: {
        Row: {
          created_at: string
          match_id: string
          round_number: number
          user_id: string
        }
        Insert: {
          created_at?: string
          match_id: string
          round_number: number
          user_id: string
        }
        Update: {
          created_at?: string
          match_id?: string
          round_number?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sabotage_draft_pick_statuses_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sabotage_draft_pick_statuses_match_id_user_id_fkey"
            columns: ["match_id", "user_id"]
            isOneToOne: false
            referencedRelation: "sabotage_draft_players"
            referencedColumns: ["match_id", "user_id"]
          },
        ]
      }
      sabotage_draft_picks: {
        Row: {
          by_timeout: boolean
          created_at: string
          display_name: string
          headshot_url: string | null
          match_id: string
          player_id: string
          round_number: number
          season: number
          user_id: string
        }
        Insert: {
          by_timeout?: boolean
          created_at?: string
          display_name: string
          headshot_url?: string | null
          match_id: string
          player_id: string
          round_number: number
          season: number
          user_id: string
        }
        Update: {
          by_timeout?: boolean
          created_at?: string
          display_name?: string
          headshot_url?: string | null
          match_id?: string
          player_id?: string
          round_number?: number
          season?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sabotage_draft_picks_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sabotage_draft_picks_match_id_round_number_fkey"
            columns: ["match_id", "round_number"]
            isOneToOne: false
            referencedRelation: "sabotage_draft_rounds"
            referencedColumns: ["match_id", "round_number"]
          },
          {
            foreignKeyName: "sabotage_draft_picks_match_id_user_id_fkey"
            columns: ["match_id", "user_id"]
            isOneToOne: false
            referencedRelation: "sabotage_draft_players"
            referencedColumns: ["match_id", "user_id"]
          },
        ]
      }
      sabotage_draft_players: {
        Row: {
          absent: boolean
          match_id: string
          seat: number
          user_id: string
        }
        Insert: {
          absent?: boolean
          match_id: string
          seat: number
          user_id: string
        }
        Update: {
          absent?: boolean
          match_id?: string
          seat?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sabotage_draft_players_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sabotage_draft_players_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      sabotage_draft_round_spins: {
        Row: {
          franchise_code: string
          match_id: string
          round_number: number
          user_id: string
        }
        Insert: {
          franchise_code: string
          match_id: string
          round_number: number
          user_id: string
        }
        Update: {
          franchise_code?: string
          match_id?: string
          round_number?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sabotage_draft_round_spins_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sabotage_draft_round_spins_match_id_round_number_fkey"
            columns: ["match_id", "round_number"]
            isOneToOne: false
            referencedRelation: "sabotage_draft_rounds"
            referencedColumns: ["match_id", "round_number"]
          },
          {
            foreignKeyName: "sabotage_draft_round_spins_match_id_user_id_fkey"
            columns: ["match_id", "user_id"]
            isOneToOne: false
            referencedRelation: "sabotage_draft_players"
            referencedColumns: ["match_id", "user_id"]
          },
        ]
      }
      sabotage_draft_rounds: {
        Row: {
          match_id: string
          round_number: number
          slot: string
        }
        Insert: {
          match_id: string
          round_number: number
          slot: string
        }
        Update: {
          match_id?: string
          round_number?: number
          slot?: string
        }
        Relationships: [
          {
            foreignKeyName: "sabotage_draft_rounds_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
        ]
      }
      sabotage_draft_standings: {
        Row: {
          losses: number
          match_id: string
          roster_strength: number
          tiebreak_rank: number
          user_id: string
          wins: number
        }
        Insert: {
          losses: number
          match_id: string
          roster_strength: number
          tiebreak_rank: number
          user_id: string
          wins: number
        }
        Update: {
          losses?: number
          match_id?: string
          roster_strength?: number
          tiebreak_rank?: number
          user_id?: string
          wins?: number
        }
        Relationships: [
          {
            foreignKeyName: "sabotage_draft_standings_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sabotage_draft_standings_match_id_user_id_fkey"
            columns: ["match_id", "user_id"]
            isOneToOne: true
            referencedRelation: "sabotage_draft_players"
            referencedColumns: ["match_id", "user_id"]
          },
        ]
      }
      sabotage_draft_tiebreak_games: {
        Row: {
          bracket_round: number
          game_number: number
          match_id: string
          player_a: string
          player_a_score: number | null
          player_b: string | null
          player_b_score: number | null
          record_wins: number
          winner_user_id: string
        }
        Insert: {
          bracket_round: number
          game_number: number
          match_id: string
          player_a: string
          player_a_score?: number | null
          player_b?: string | null
          player_b_score?: number | null
          record_wins: number
          winner_user_id: string
        }
        Update: {
          bracket_round?: number
          game_number?: number
          match_id?: string
          player_a?: string
          player_a_score?: number | null
          player_b?: string | null
          player_b_score?: number | null
          record_wins?: number
          winner_user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sabotage_draft_tiebreak_games_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sabotage_draft_tiebreak_games_match_id_player_a_fkey"
            columns: ["match_id", "player_a"]
            isOneToOne: false
            referencedRelation: "sabotage_draft_players"
            referencedColumns: ["match_id", "user_id"]
          },
          {
            foreignKeyName: "sabotage_draft_tiebreak_games_match_id_player_b_fkey"
            columns: ["match_id", "player_b"]
            isOneToOne: false
            referencedRelation: "sabotage_draft_players"
            referencedColumns: ["match_id", "user_id"]
          },
          {
            foreignKeyName: "sabotage_draft_tiebreak_games_match_id_winner_user_id_fkey"
            columns: ["match_id", "winner_user_id"]
            isOneToOne: false
            referencedRelation: "sabotage_draft_players"
            referencedColumns: ["match_id", "user_id"]
          },
        ]
      }
      sabotage_draft_x_factor_decisions: {
        Row: {
          created_at: string
          match_id: string
          replace_slot: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          match_id: string
          replace_slot?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          match_id?: string
          replace_slot?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sabotage_draft_x_factor_decisions_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "matches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sabotage_draft_x_factor_decisions_match_id_user_id_fkey"
            columns: ["match_id", "user_id"]
            isOneToOne: true
            referencedRelation: "sabotage_draft_players"
            referencedColumns: ["match_id", "user_id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      choose_post_game: {
        Args: {
          p_choice: Database["public"]["Enums"]["post_game_choice"]
          p_match_id: string
          p_roster_preset?: string
          p_scoring_mode?: string
          p_season_from?: number
          p_season_to?: number
        }
        Returns: {
          choice: Database["public"]["Enums"]["post_game_choice"]
          chosen_at: string
          match_id: string
          next_match_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "post_game_actions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      claim_guest_identity: { Args: never; Returns: string }
      close_lobby: { Args: { p_lobby_id: string }; Returns: undefined }
      create_lobby: {
        Args: never
        Returns: {
          closed_at: string | null
          code: string
          created_at: string
          host_id: string
          id: string
          selected_game: string | null
        }
        SetofOptions: {
          from: "*"
          to: "lobbies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      delete_own_account: { Args: never; Returns: undefined }
      heartbeat_lobby: { Args: { p_lobby_id: string }; Returns: undefined }
      join_lobby: {
        Args: { p_code: string }
        Returns: {
          closed_at: string | null
          code: string
          created_at: string
          host_id: string
          id: string
          selected_game: string | null
        }
        SetofOptions: {
          from: "*"
          to: "lobbies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      leave_lobby: { Args: { p_lobby_id: string }; Returns: undefined }
      lobby_member_match_history: {
        Args: { p_lobby_id: string }
        Returns: Database["public"]["CompositeTypes"]["match_history_row"][]
        SetofOptions: {
          from: "*"
          to: "match_history_row"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      my_match_history: {
        Args: never
        Returns: {
          ended_at: string
          game: string
          match_id: string
          mode: Database["public"]["Enums"]["run_mode"]
          placement: number
          raw_score: number
        }[]
      }
      my_profile_knower_highlights: {
        Args: never
        Returns: {
          percentile: number
          total_points: number
          window_key: string
        }[]
      }
      pause_match: {
        Args: { p_match_id: string }
        Returns: {
          ended_at: string | null
          game: string
          id: string
          paused_at: string | null
          run_id: string
          seq: number
          started_at: string | null
          status: Database["public"]["Enums"]["match_status"]
        }
        SetofOptions: {
          from: "*"
          to: "matches"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      record_guest_account_collision: {
        Args: { p_nonce: string }
        Returns: undefined
      }
      resume_match: {
        Args: { p_match_id: string }
        Returns: {
          ended_at: string | null
          game: string
          id: string
          paused_at: string | null
          run_id: string
          seq: number
          started_at: string | null
          status: Database["public"]["Enums"]["match_status"]
        }
        SetofOptions: {
          from: "*"
          to: "matches"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      select_lobby_game: {
        Args: { p_game: string; p_lobby_id: string }
        Returns: undefined
      }
      start_run: {
        Args: {
          p_game: string
          p_lobby_id: string
          p_mode: Database["public"]["Enums"]["run_mode"]
        }
        Returns: {
          ended_at: string | null
          game: string
          id: string
          paused_at: string | null
          run_id: string
          seq: number
          started_at: string | null
          status: Database["public"]["Enums"]["match_status"]
        }
        SetofOptions: {
          from: "*"
          to: "matches"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      start_solo_run: {
        Args: { p_game: string }
        Returns: {
          ended_at: string | null
          game: string
          id: string
          paused_at: string | null
          run_id: string
          seq: number
          started_at: string | null
          status: Database["public"]["Enums"]["match_status"]
        }
        SetofOptions: {
          from: "*"
          to: "matches"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      match_status: "setup" | "playing" | "complete" | "abandoned" | "paused"
      post_game_choice: "replay" | "lobby"
      run_mode: "arcade" | "party" | "solo"
      run_status: "active" | "finished" | "abandoned"
    }
    CompositeTypes: {
      match_history_row: {
        user_id: string | null
        match_id: string | null
        game: string | null
        ended_at: string | null
        placement: number | null
        raw_score: number | null
      }
    }
  }
  sabotage_draft: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      mark_absent: { Args: { p_match_id: string }; Returns: undefined }
      options: {
        Args: { p_match_id: string; p_target_user_id?: string }
        Returns: {
          display_name: string
          headshot_url: string
          player_id: string
          season: number
          slot_category: string
        }[]
      }
      pick_avs: {
        Args: { p_match_id: string }
        Returns: {
          av: number
          round_number: number
          user_id: string
        }[]
      }
      start: {
        Args: { p_match_id: string }
        Returns: Database["sabotage_draft"]["CompositeTypes"]["round"]
        SetofOptions: {
          from: "*"
          to: "round"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      state: {
        Args: { p_match_id: string }
        Returns: Database["sabotage_draft"]["CompositeTypes"]["round"]
        SetofOptions: {
          from: "*"
          to: "round"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      submit_guess: {
        Args: {
          p_match_id: string
          p_player_id: string
          p_replacement_player_id?: string
          p_replacement_season?: number
          p_season?: number
        }
        Returns: Database["public"]["Tables"]["sabotage_draft_guesses"]["Row"]
        SetofOptions: {
          from: "*"
          to: "sabotage_draft_guesses"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      submit_pass: {
        Args: { p_match_id: string }
        Returns: Database["public"]["Tables"]["sabotage_draft_passes"]["Row"]
        SetofOptions: {
          from: "*"
          to: "sabotage_draft_passes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      submit_pick: {
        Args: { p_match_id: string; p_player_id: string; p_season: number }
        Returns: Database["public"]["Tables"]["sabotage_draft_picks"]["Row"]
        SetofOptions: {
          from: "*"
          to: "sabotage_draft_picks"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      submit_x_factor_decision: {
        Args: { p_match_id: string; p_replace_slot?: string }
        Returns: Database["public"]["Tables"]["sabotage_draft_x_factor_decisions"]["Row"]
        SetofOptions: {
          from: "*"
          to: "sabotage_draft_x_factor_decisions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      tick: {
        Args: { p_match_id: string }
        Returns: Database["sabotage_draft"]["CompositeTypes"]["round"]
        SetofOptions: {
          from: "*"
          to: "round"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      guess_result: "miss" | "respun" | "sabotaged"
    }
    CompositeTypes: {
      round: {
        match_id: string | null
        round_count: number | null
        current_round: number | null
        slot: string | null
        server_now: string | null
        x_factor_open: boolean | null
        active_user_id: string | null
        turn_deadline: string | null
      }
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  auction: {
    Enums: {},
  },
  graphql_public: {
    Enums: {},
  },
  higher_or_lower: {
    Enums: {},
  },
  prompts: {
    Enums: {},
  },
  public: {
    Enums: {
      match_status: ["setup", "playing", "complete", "abandoned", "paused"],
      post_game_choice: ["replay", "lobby"],
      run_mode: ["arcade", "party", "solo"],
      run_status: ["active", "finished", "abandoned"],
    },
  },
  sabotage_draft: {
    Enums: {
      guess_result: ["miss", "respun", "sabotaged"],
    },
  },
} as const

